module Knapsack
  module Runners
    class RSpecRunner
      def self.run(args)
        allocator = Knapsack::AllocatorBuilder.new(Knapsack::Adapters::RspecAdapter).allocator

        puts
        puts 'Report specs:'
        puts allocator.report_node_tests
        puts
        puts 'Leftover specs:'
        puts allocator.leftover_node_tests
        puts

        num = max_process_count
        if num > 1 && !skip_parallel?
          test_slices = allocator.distribute_files(num)
          if test_slices.length > 1
            begin
              puts "Tests will be parallelized into #{test_slices.length} processes"
              good = Knapsack::Parallelizer::RSpecParallelizer.run(test_slices, args: args)
              exit(good ? 0 : 12)
            rescue => e
              puts e.message
              puts e.backtrace.join("\n\t")
              exit(1)
            end
          end
        end
        if allocator.stringify_node_tests.empty?
          cmd = 'true'
          puts 'No tests to run, check knapsack_all_tests_file_names'
        else
          cmd = if ENV['ENABLE_BELUGA'] == 'true' && ENV['JS_DRIVER'] == 'selenium-chrome'
            path = File.expand_path("../../plugins/rake-runner/rb", Dir.pwd)
            if ENV['ENABLE_LIGHTNING'] == 'true'
              envs = "TEST_ENV_NUM=#{max_process_count} #{"TC_PLUGIN_PATH=#{path}" if Dir.exists?(path)}"
              "#{envs} beluga -X=--name -X=beluga_#{ENV['BUILD_NUMBER']} turnip_lightning #{args} #{allocator.stringify_node_tests}"
            else
              "#{"TC_PLUGIN_PATH=#{path}" if Dir.exists?(path)} beluga -X='--name' -X=beluga_#{ENV['BUILD_NUMBER']} turnip #{args} #{allocator.stringify_node_tests}"
            end
          elsif ENV['ENABLE_LIGHTNING'] == 'true' && ENV['JS_DRIVER'] == 'selenium-chrome'
            lightning_path = "devscripts/teamcity/ci-scripts/lib/lightning"
            if Dir.exists?(lightning_path)
              path = File.expand_path("../../plugins/rake-runner/rb", Dir.pwd)
              opts = Dir.exists?(path) ? "-I #{path}/patch/common -I #{path}/patch/testunit -I #{path}/patch/bdd --deprecation-out tmp/artifacts/deprecations.log" : ''
              envs = "LIGHTNING_START=true TEST_ENV_NUM=#{max_process_count} LIGHTNING_STRIKES=#{lightning_path}"
              "#{envs} bundle exec ruby #{lightning_path}/rspec_server.rb start #{args} #{opts} && " +
                "bundle exec ruby #{lightning_path}/tc_parallel.rb #{allocator.stringify_node_tests}"
            else
              puts "'#{lightning_path}' directory not found in the app directory. Unable to start lightning."
              exit(1)
            end
          else
            %Q[bundle exec rspec -r turnip/rspec -r turnip/capybara #{args}  #{allocator.stringify_node_tests}]
          end
        end
        Knapsack::Util.run_cmd(cmd)
        exit($?.exitstatus)
      end

      # Number of CPUs for this machine
      def self.ncpu
        #sysctl for OSX, nproc for linux
        num = RUBY_PLATFORM.include?('darwin') ? `sysctl -n hw.ncpu`.to_i : `nproc`.to_i
        num <= 1 ? 1 : num
      rescue Errno::ENOENT
        1
      end

      # Maximum number of processes allowed for this agent
      def self.max_process_count
        # Default is 2 agents per instance
        default_agent_count = 2
        num_agents = (ENV['NUM_AGENTS_PER_INSTANCE'] || default_agent_count).to_i
        num = (ncpu.to_f / (num_agents < 1 ? default_agent_count : num_agents)).ceil
        max = ENV['MAX_PROCESS_PER_AGENT'].to_i
        num = max if max > 0 && num > max
        num <= 1 ? 1 : num
      end

      def self.skip_parallel?
        ENV['JS_DRIVER'] == 'selenium-ie-remote' || Knapsack::Util.to_bool(ENV['SKIP_PARALLEL']) || ENV['ENABLE_LIGHTNING'] == 'true'
      end
    end
  end
end

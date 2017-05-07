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
              Knapsack::Parallelizer::RSpecParallelizer.run(test_slices, args: args)
              exit(0)
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
          files = allocator.stringify_node_tests
          cmd = %Q[bundle exec rspec -r turnip/rspec -r turnip/capybara #{args} #{files}]
        end
        system(cmd)
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
        num = (ncpu.to_f / (num_agents == 0 ? default_agent_count : num_agents)).ceil
        num <= 1 ? 1 : num
      end

      def self.skip_parallel?
        ENV['JS_DRIVER'] == 'selenium-ie-remote' || Knapsack::Util.to_bool(ENV['SKIP_PARALLEL'])
      end
    end
  end
end

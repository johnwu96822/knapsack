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

        num = num_of_forks
        if num > 1 && !skip_parallel?
          test_slices = allocator.split_tests(num)
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

      def self.ncpu
        #sysctl for OSX, nproc for linux
        RUBY_PLATFORM.include?('darwin') ? `sysctl -n hw.ncpu`.to_i : `nproc`.to_i
      rescue Errno::ENOENT
        1
      end

      def self.num_of_forks
        # Default is 2 agents per instance
        default_num = 2
        num_agents = (ENV['NUM_AGENTS_PER_INSTANCE'] || default_num).to_i
        num = (ncpu.to_f / (num_agents == 0 ? default_num : num_agents)).ceil
      end

      def self.skip_parallel?
        ENV['JS_DRIVER'] == 'selenium-ie-remote'
      end
    end
  end
end

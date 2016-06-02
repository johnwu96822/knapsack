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

        if allocator.stringify_node_tests.empty?
          cmd = 'true'
          puts 'No tests to run, check knapsack_all_tests_file_names'
        else
          cmd = %Q[bundle exec rspec -r turnip/rspec -r turnip/capybara #{args}  #{allocator.stringify_node_tests}]
        end

        system(cmd)
        exit($?.exitstatus)
      end
    end
  end
end

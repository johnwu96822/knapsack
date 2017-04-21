module Knapsack
  class Allocator
    def initialize(args={})
      @report_distributor = Knapsack::Distributors::ReportDistributor.new(args)
      @leftover_distributor = Knapsack::Distributors::LeftoverDistributor.new(args)
    end

    def report_node_tests
      @report_node_tests ||= @report_distributor.tests_for_current_node
    end

    def leftover_node_tests
      @leftover_node_tests ||= @leftover_distributor.tests_for_current_node
    end

    def node_tests
      @node_tests ||= report_node_tests + leftover_node_tests
    end

    def stringify_node_tests
      node_tests.join(' ')
    end

    def test_dir
      @report_distributor.test_file_pattern.gsub(/^(.*?)\//).first
    end

    def split_tests(num)
      files = node_tests
      return [files] if num <= 1 || files.length < 5
      if num >= files.length
        files_sliced = files.each_slice(1).to_a
        num = files_sliced.length
      else
        files_sliced = []
        # Slice the test files to evenly distribute them among "num" of slices
        size = files.length / num
        remain = files.length % num
        index = 0
        num.times do |i|
          end_index = index + size - 1
          if remain > 0
            end_index += 1
            remain -= 1
          end
          files_sliced << files[index..end_index]
          index = end_index + 1
        end
      end
      files_sliced[0..num - 1]
    end
  end
end

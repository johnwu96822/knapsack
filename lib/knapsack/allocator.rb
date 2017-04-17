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
      return [node_tests] if num <= 1 || node_tests.length < 5
      files = node_tests.shuffle
      if num >= files.length
        files_sliced = files.each_slice(1).to_a
        num = files_sliced.length
      else
        # Slice the test files to evenly distribute them among "num" of slices
        files_sliced = files.each_slice(files.length / num).to_a
        # Even spread the remaining files if there are
        if files_sliced.length == num + 1
          files_sliced[num].each_with_index do |arr, index|
            files_sliced[index] << arr
          end
        end
      end
      files_sliced[0..num - 1]
    end
  end
end

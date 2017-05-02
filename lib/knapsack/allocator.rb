module Knapsack
  class Allocator
    # The maximum number of files allowed to run without parallelization
    PARALLEL_THRESHOLD = 2
    MINIMUM_PER_PROCESS = 1

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

    def split_tests(no_of_processes)
      files = node_tests
      no_of_processes = determine_no_of_processes(files.length, no_of_processes)
      return [files] if no_of_processes <= 1 || files.length <= PARALLEL_THRESHOLD

      files_sliced = []
      # Slice the test files to evenly distribute them among "no_of_processes" of slices
      size = files.length / no_of_processes
      remain = files.length % no_of_processes
      index = 0
      no_of_processes.times do |i|
        end_index = index + size - 1
        if remain > 0
          end_index += 1
          remain -= 1
        end
        files_sliced << files[index..end_index]
        index = end_index + 1
      end
      files_sliced[0..no_of_processes - 1]
    end

    # Give at least 2 files per process by adjusting the number of processes.
    def determine_no_of_processes(size, no_of_processes)
      return 1 if no_of_processes < 1 || size <= PARALLEL_THRESHOLD
      per_slice = size / no_of_processes
      # Try to get more than 2 files per process
      while per_slice < MINIMUM_PER_PROCESS && no_of_processes > 1
        no_of_processes -= 1
        per_slice = size / no_of_processes
      end
      no_of_processes
    end
  end
end

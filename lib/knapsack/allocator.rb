module Knapsack
  class Allocator
    # The maximum number of files allowed to run in a single process without parallelization
    PARALLEL_THRESHOLD = 2
    # The minimum number of files a process should have. A process is not needed
    # if it cannot be allocated up to this number of files.
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

    # Split the tests in this allocator by:
    # 1. Adjusting the number of processes to use based on the number of file, in
    #    case there are more processes than files.
    # 2. Evenly distributing the files between the processes and maintain the order
    #    of test files within each process.
    def distribute_files(max_process_count)
      files = node_tests
      number_of_processes = determine_number_of_processes(files.length, max_process_count)
      return [files] if number_of_processes <= 1 || files.length <= PARALLEL_THRESHOLD

      # Slice the test files to evenly distribute them among "no_of_processes" of slices
      files_sliced = []
      size = files.length / number_of_processes
      remain = files.length % number_of_processes
      index = 0
      number_of_processes.times do |i|
        end_index = index + size - 1
        if remain > 0
          end_index += 1
          remain -= 1
        end
        files_sliced << files[index..end_index]
        index = end_index + 1
      end
      files_sliced
    end

    # Give at least MINIMUM_PER_PROCESS files per process by adjusting the number of processes.
    def determine_number_of_processes(size, number_of_processes)
      return 1 if number_of_processes < 1 || size <= PARALLEL_THRESHOLD
      per_slice = size / number_of_processes
      # Try to get more than MINIMUM_PER_PROCESS files per process by reducing the
      # number of processes until files per process is more than the minimum
      while per_slice < MINIMUM_PER_PROCESS && number_of_processes > 1
        number_of_processes -= 1
        per_slice = size / number_of_processes
      end
      number_of_processes
    end

  end
end

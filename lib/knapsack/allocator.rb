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
    # 2. Evenly distributing the files by their sizes with the zig-zag fashion.
    #    This is to hope that each process would get more even number of tests,
    #    assuming the number of tests is related to the size of their files.
    def distribute_files(max_process_count)
      files = node_tests
      number_of_processes = determine_number_of_processes(files.length, max_process_count)
      return [files] if number_of_processes <= 1 || files.length <= PARALLEL_THRESHOLD

      files = sort_by_file_time(files)
      # Slice the test files to evenly distribute them among "number_of_processes" of slices
      files_sliced = []
      index = 0
      # Zig-zag distribute the files which have been sorted by file size
      files.each_with_index do |f, i|
        if files_sliced[index].nil?
          files_sliced[index] = [f]
        else
          files_sliced[index] << f
        end
        if (i / number_of_processes) % 2 == 0
          index += 1 if index < number_of_processes - 1
        else
          index -= 1 if index > 0
        end
      end
      files_sliced
    end

    # Give at least MINIMUM_PER_PROCESS files per process by adjusting the number of processes.
    def determine_number_of_processes(size, number_of_processes)
      return 1 if number_of_processes < 1 || size <= PARALLEL_THRESHOLD
      per_slice = size / number_of_processes
      # Try to get more than MINIMUM_PER_PROCESS files per process
      while per_slice < MINIMUM_PER_PROCESS && number_of_processes > 1
        number_of_processes -= 1
        per_slice = size / number_of_processes
      end
      number_of_processes
    end

    # Sort files by their sizes in descending order
    def sort_by_file_time(filenames)
      files_with_time = []
      files_with_sizes = []
      report = @report_distributor.report
      filenames.each do |f|
        time = report[f]
        if time.nil?
          # Use bloated file size for files without a reported time
          size = File.size?(f)
          files_with_sizes << {file: f, size: size.nil? ? 0 : size}
        else
          files_with_time << {file: f, time: time}
        end
      end
      files_with_time.sort!{|a, b| b[:time] <=> a[:time] }
      files_with_sizes.sort!{|a, b| b[:size] <=> a[:size] }
      puts "Files with report time: #{files_with_time}" if to_bool(ENV['VERBOSE'])
      puts "Files with report sizes: #{files_with_sizes}" if to_bool(ENV['VERBOSE'])
      (files_with_time + files_with_sizes).collect{ |f| f[:file] }
    end

  end
end

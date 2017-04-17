module Knapsack::Parallelizer
  class Base
    class << self
      # The first fork process will use the same resources as the single process,
      # including the database name and the failure log file. Other forks will
      # use resources with a process identifier plus an index (starting with 1) to
      # distinguish their database names and failure log files. The failure log
      # files will be combined at the end.
      def run(test_slices, options = {})
        # The first process will use the database name in the database.yml file.
        # Other processes will use the database name appended with this identifier plus
        # an index, starting with 1, 2, 3...
        identifier = "_#{Process.pid}_"

        forks = test_slices.length
        setup(forks, identifier, options)
        begin
          run_tests(test_slices, identifier, options)
        rescue => e
          puts e.message
          puts e.backtrace.join("\n\t")
        ensure
          clean_up(forks, identifier, options)
        end
      end

      def setup(num, identifier, options = {})
        # To be overriden
      end

      def clean_up(num, identifier, options = {})
        # To be overriden
      end

      def test(test_slices, index, identifier, options)
        # To be overriden
      end

      protected

      # test_slices is an array of filename arrays. Each filename list is to be
      # run parallely by a process.
      # identifier is the current process's identifier that will be used to further
      # distinguish each fork's database name.
      def run_tests(test_slices, identifier, options = {})
        forks = test_slices.length
        options[:time] = Time.now
        if forks > 1
          pids = []
          forks.times do |i|
            pids << fork do
              test(test_slices, i, identifier, options)
              # Force the fork to end without running at_exit bindings
              Kernel.exit!
            end
          end
          # Wait for the forks to finish the tests
          pids.each {|pid| Process.wait(pid)}
        else
          test(test_slices, 0, identifier, options)
        end
      end

    end
  end
end

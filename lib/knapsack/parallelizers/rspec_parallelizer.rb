module Knapsack::Parallelizer
  class RSpecParallelizer
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
        worker_count = test_slices.length
        # This file will be read and used in clean_up
        system("echo #{worker_count},#{identifier} > tmp/parallel_identifier.txt")

        setup(worker_count, identifier, options)
        run_tests(test_slices, identifier, options)
      rescue => e
        puts e.message
        puts e.backtrace.join("\n\t")
      ensure
        puts
        combine_failures(worker_count, identifier)
        clean_up
        if File.exists?("tmp/error_forked_rspec")
          puts
          puts "Some forked rspec processes exited with error code:"
          puts "Process index:Exit code"
          system("cat 'tmp/error_forked_rspec'")
          return false
        end
        return true
      end

      # This runs within the forked processes
      def test(test_slices, index, identifier, options)
        # For processes other than the very first one, fork_identifier is used
        # as the last portion of the database name and also part of the failure
        # log file names.
        fork_identifier = index > 0 ? "#{identifier}#{index}" : ""
        # Use time for the regular (not failure) log file names so that when running
        # it locally, it would not overwrite the previous log files
        log_file = "tmp/knapsack_#{options[:time].to_i}_#{index}.log"
        # Set 10 seconds apart for each build to avoid Bootsnap problem
        sleep(index * 10) if index > 0
        status = Knapsack::Util.run_cmd("#{'TC_PARALLEL_ID='+fork_identifier if index > 0} bundle exec rspec -r turnip/rspec -r turnip/capybara #{options[:args]} #{test_slices[index].join(' ')} > #{log_file}")
        unless status
          code = $?
          open('tmp/error_forked_rspec', 'a') do |f|
            f.puts "#{index}:#{code}"
          end
        end

        puts
        puts "******* Parallel testing #{index + 1}/#{test_slices.length} finished ********"
        system("cat #{log_file}")
        system("rm #{log_file}")

        failures = File.read("tmp/integration#{fork_identifier}.failures")
        puts(failures.present? ? "Failed files:\n#{failures}" : "All test files passed")
      end

      # Duplicating test databases for forks other than the first one, since the first fork uses
      # the main database (the one we are duplicating from, without the added identifier)
      def setup(num, identifier, options = {})
        return if num <= 1
        db_config = YAML.load(ERB.new(File.read('config/database.yml')).result)['test']

        filename = "tmp/testdb.sql"
        options = db_options(db_config)
        Knapsack::Util.run_cmd("mysqldump #{options} #{db_config['database']} > #{filename}")

        # The first process will use the origin/main database, instead of one that is
        # appeneded with additional index. Hence the (num - 1) here
        (num - 1).times do |i|
          db_name = "#{db_config['database']}#{identifier}#{i + 1}"
          Knapsack::Util.run_cmd("mysqladmin #{options} create #{db_name}")
          Knapsack::Util.run_cmd("mysql #{options} #{db_name} < #{filename}")
        end
      end

      def clean_up
        clean_up_processes
        clean_up_databases
        clean_up_logs
      end

      protected

      # test_slices is an array of filename arrays. Each filename list is to be
      # run parallely by a process.
      # identifier is the current process's identifier that will be used to further
      # distinguish each fork's database name.
      def run_tests(test_slices, identifier, options = {})
        worker_count = test_slices.length
        options[:time] = Time.now
        if worker_count > 1
          pids = []
          worker_count.times do |i|
            pids << fork do
              begin
                test(test_slices, i, identifier, options)
              ensure
                system("rm tmp/parallel_pids/#{Process.pid}")
                # Force the fork to end without running at_exit bindings
                Kernel.exit!
              end
            end
          end
          system("mkdir tmp/parallel_pids")
          pid_files = pids.collect{|pid| "tmp/parallel_pids/#{pid}"}.join(' ')
          Knapsack::Util.run_cmd("touch #{pid_files}")
          # Wait for the forks to finish the tests
          pids.each {|pid| Process.wait(pid)}
        else
          test(test_slices, 0, identifier, options)
        end
      end

      private

      def db_options(db_config)
        "-u #{db_config['username']} #{db_config['password'].blank? ? '' : '-p'+db_config['password']} #{db_config['host'].blank? ? '' : '-h'+db_config['host']} #{db_config['port'].blank? ? '' : '-P'+db_config['port']} #{db_config['socket'].blank? ? '' : '--socket='+db_config['socket']}"
      end

      # Clean up the duplicated databases but not the main one, which will be dropped
      # in a later step.
      def clean_up_dbs(num, identifier)
        return if num <= 1
        db_config = YAML.load(ERB.new(File.read('config/database.yml')).result)['test']
        (num - 1).times do |i|
          db_name = "#{db_config['database']}#{identifier}#{i + 1}"
          begin
            Knapsack::Util.run_cmd("mysqladmin #{db_options(db_config)} -f drop #{db_name}")
          rescue => e
            puts e.message
            puts e.backtrace.join("\n\t")
          end
        end
      end

      # Combines the failure files into the main one, which will then be used
      # by the rerun step.
      def combine_failures(num, identifier)
        return if num <= 1
        target = 'tmp/integration.failures'
        (num - 1).times do |i|
          # Files start from 1, not 0. Hence the i + 1
          from = "tmp/integration#{identifier}#{i + 1}.failures"
          begin
            Knapsack::Util.run_cmd("cat #{from} >> #{target}") if File.exist?(from)
          rescue => e
            puts e.message
            puts e.backtrace.join("\n\t")
          end
        end
      end

      def clean_up_processes
        return unless Dir.exist?('tmp/parallel_pids')
        Dir.glob("tmp/parallel_pids/*") do |path|
          filename = File.basename(path)
          if filename =~ /^\d+$/
            puts "Cleaning up the forked processes: #{filename}"
            begin
              Process.kill('KILL', filename.to_i)
            rescue => e
              puts e.message
            end
          end
        end
        system("rm -Rf tmp/parallel_pids")
      end

      def clean_up_databases
        return unless File.exist?('tmp/parallel_identifier.txt')
        data = `cat tmp/parallel_identifier.txt`
        unless data.empty?
          puts "Cleaning up the duplicated database(s): #{data}"
          values = data.strip.split(',')
          clean_up_dbs(values[0].to_i, values[1])
        end
        system("rm -f tmp/parallel_identifier.txt")
      end

      def clean_up_logs
        # Output the logs that were not displayed due to the rspec process getting killed
        Dir.glob("tmp/knapsack_*_*.log") do |filename|
          puts
          puts "************* Unfinished Test: #{filename} **************"
          system("cat #{filename}")
          puts "******* END OF #{filename} ********"
          system("rm -f #{filename}")
        end
      end

    end
  end
end

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
        forks = test_slices.length
        # This file will be read and used in clean_up
        system("echo #{forks},#{identifier} > tmp/parallel_identifier.txt")

        setup(forks, identifier, options)
        run_tests(test_slices, identifier, options)
      rescue => e
        puts e.message
        puts e.backtrace.join("\n\t")
      ensure
        combine_failures(forks, identifier)
      end

      def test(test_slices, index, identifier, options)
        #sleep(index * 12)
        # For processes other than the very first one, fork_identifier is used
        # as the last portion of the database name and also part of the failure
        # log file names.
        fork_identifier = "#{identifier}#{index}"
        # Use time for the regular (not failure) log file names so that when running
        # it locally, it would not overwrite the previous log files
        log_file = "tmp/knapsack_#{options[:time].to_i}_#{index}.log"
        run_cmd("#{'TC_PARALLEL_ID='+fork_identifier if index > 0} bundle exec rspec -r turnip/rspec -r turnip/capybara #{options[:args]} #{test_slices[index].join(' ')} > #{log_file}")
        `echo "******* Parallel testing #{index}/#{test_slices.length} finished ********" >> #{log_file}`
        system("cat #{log_file}")
        system("rm #{log_file}")
      end

      # Duplicating test databases for forks other than the first one, since the first fork uses
      # the main database (the one we are duplicating from, without the added identifier)
      def setup(num, identifier, options = {})
        # Generate the integration db script that will be reloaded before every test
        run_cmd("RAILS_ENV=test bundle exec rake integration_test:setup_db")
        db_config = YAML.load(ERB.new(File.read('config/database.yml')).result)['test']
        return db_config if num <= 1

        filename = "tmp/testdb.sql"
        options = db_options(db_config)
        run_cmd("mysqldump #{options} #{db_config['database']} > #{filename}")

        (num - 1).times do |i|
          db_name = "#{db_config['database']}#{identifier}#{i + 1}"
          run_cmd("mysqladmin #{options} create #{db_name}")
          run_cmd("mysql #{options} #{db_name} < #{filename}")
        end
      end

      def clean_up
        # Output the logs that were not displayed due to the rspec process getting killed
        system("cat tmp/knapsack_*_*.log")

        puts '************* Clean up **************'

        if File.exist?('tmp/parallel_pids.txt')
          data = `cat tmp/parallel_pids.txt`
          unless data.empty?
            puts "Cleaning up the forked processes: #{data}"
            pids = data.strip.split(',').collect{|i| i.to_i }
            begin
              Process.kill('KILL', *pids) unless pids.empty?
            rescue => e
              puts e.message
            end
          end
        end

        if File.exist?('tmp/parallel_identifier.txt')
          data = `cat tmp/parallel_identifier.txt`
          unless data.empty?
            puts "Cleaning up the duplicated database(s): #{data}"
            values = data.strip.split(',')
            clean_up_dbs(values[0].to_i, values[1])
          end
        end
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
              begin
                test(test_slices, i, identifier, options)
              ensure
                remove_pid(Process.pid)
                # Force the fork to end without running at_exit bindings
                Kernel.exit!
              end
            end
          end
          system("echo #{pids.join(',')} > tmp/parallel_pids.txt")
          # Wait for the forks to finish the tests
          pids.each {|pid| Process.wait(pid)}
        else
          test(test_slices, 0, identifier, options)
        end
      end

      private

      def run_cmd(cmd)
        puts cmd
        system(cmd)
      end

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
            run_cmd("mysqladmin #{db_options(db_config)} -f drop #{db_name}")
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
            if File.exist?(from)
              run_cmd("cat #{from} >> #{target}")
              # File.delete(from)
            end
          rescue => e
            puts e.message
            puts e.backtrace.join("\n\t")
          end
        end
      end

      def remove_pid(pid)
        if File.exist?('tmp/parallel_pids.txt')
          values = `cat tmp/parallel_pids.txt`.strip.split(',')
          values.delete(pid.to_s)
          if values.empty?
            system("rm -f tmp/parallel_pids.txt")
          else
            system("echo #{values.join(',')} > tmp/parallel_pids.txt")
          end
        end
      end

    end
  end
end

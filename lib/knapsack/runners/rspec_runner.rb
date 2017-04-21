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
        if num > 1
          test_slices = allocator.split_tests(num)
          if test_slices.length > 1
            begin
              puts "Tests will be parallelized into #{test_slices.length} processes"
              Parallelizer.run(args, test_slices)
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
        num_agents = (ENV['NUM_AGENTS_PER_INSTANCE'] || 2).to_i
        num = (ncpu.to_f / (num_agents == 0 ? 2 : num_agents)).ceil
      end
    end

    class Parallelizer
      class << self
        # The first fork process will use the same resources as the single process,
        # including the database name and the failure log file. Other forks will
        # use resources with a process identifier plus an index (starting with 1) to
        # distinguish their database names and failure log files. The failure log
        # files will be combined at the end.
        def run(args, test_slices)
          # The first process will use the database name in the database.yml file.
          # Other processes will use the database name appended with this identifier plus
          # an index, starting with 1, 2, 3...
          identifier = "_#{Process.pid}_"

          forks = test_slices.length
          db_config = duplicate_dbs(forks, identifier)
          run_tests(args, test_slices, identifier, db_config)
        end

        private

        # Duplicating test databases for forks other than the first one, since the first fork uses
        # the main database (the one we are duplicating from, without the added identifier)
        def duplicate_dbs(num, identifier)
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
          db_config
        end

        # test_slices is an array of filename arrays. Each filename list is to be
        # run parallely by a process.
        # identifier is the current process's identifier that will be used to further
        # distinguish each fork's database name.
        # db_config is a hash of config values from database.yml
        def run_tests(args, test_slices, identifier, db_config)
          forks = test_slices.length
          pids = []
          time = Time.now.to_i
          forks.times do |i|
            pids << fork do
              index = i
              sleep(index * 8)
              # For processes other than the very first one, fork_identifier is used
              # as the last portion of the database name and also part of the failure
              # log file names.
              fork_identifier = "#{identifier}#{index}"
              # Use time for the regular (not failure) log file names so that when running
              # it locally, it would not overwrite the previous log files
              log_file = "knapsack#{time}_#{index}.log"
              run_cmd("#{'TC_PARALLEL_ID='+fork_identifier if index > 0} bundle exec rspec -r turnip/rspec -r turnip/capybara #{args} #{test_slices[index].join(' ')} > #{log_file}")

              puts '**********************************'
              puts "Parallel testing #{index} finished"
              system("cat #{log_file}")

              # Force the fork to end without running at_exit bindings
              Kernel.exit!
            end
          end
          # Wait for the forks to finish the tests
          pids.each {|pid| Process.wait(pid)}
        rescue => e
          puts e.message
          puts e.backtrace.join("\n\t")
        ensure
          combine_failures(forks, identifier)
          clean_up_dbs(forks, identifier, db_config)
        end

        def run_cmd(cmd)
          puts cmd
          system(cmd)
        end

        def db_options(db_config)
          "-u #{db_config['username']} #{db_config['password'].blank? ? '' : '-p'+db_config['password']} #{db_config['host'].blank? ? '' : '-h'+db_config['host']} #{db_config['port'].blank? ? '' : '-P'+db_config['port']} #{db_config['socket'].blank? ? '' : '--socket='+db_config['socket']}"
        end

        def clean_up_dbs(num, identifier, db_config)
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

      end
    end

  end
end

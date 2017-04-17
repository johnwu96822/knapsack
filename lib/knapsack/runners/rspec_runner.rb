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
        def run(args, test_slices)
          forks = test_slices.length

          # The first process will use the database name in the database.yml file.
          # Other processes will use the database name appended with this identifier plus
          # an index, starting with 1, 2, 3...
          identifier = "_#{Process.pid}_"

          db_config = duplicate_dbs(forks, identifier)
          run_tests(args, test_slices, identifier, db_config)
        end

        private

        def duplicate_dbs(num, identifier)
          db_config = YAML.load(ERB.new(File.read('config/database.yml')).result)['test']
          return db_config if num <= 1

          filename = "tmp/testdb.sql"
          options = db_options(db_config)
          puts "mysqldump #{options} #{db_config['database']} > #{filename}"
          system("mysqldump #{options} #{db_config['database']} > #{filename}")

          # Create test databases except for the first fork. Let the first fork use
          # the main database (without the added identifier)
          (num - 1).times do |i|
            db_name = "#{db_config['database']}#{identifier}#{i + 1}"
            puts "mysqladmin #{options} create #{db_name}"
            system("mysqladmin #{options} create #{db_name}")
            puts "mysql #{options} #{db_name} < #{filename}"
            system("time mysql #{options} #{db_name} < #{filename}")
          end
          sleep(3)
          db_config
        end

        def run_tests(args, test_slices, identifier, db_config)
          forks = test_slices.length
          pids = []
          time = Time.now.to_i
          file_list = []
          forks.times do |i|
            pids << fork do
              index = i
              sleep(index * 3)
              # For processes other than the very first one, fork_identifier is used
              # as the last portion of the database name and also part of the failure
              # log file names.
              fork_identifier = "#{identifier}#{index}"
              # Use time for the regular (not failure) log file names so that when running
              # it locally, it would not overwrite the previous log files
              log_file = "knapsack#{time}_#{index}.log"
              file_list << log_file
              puts "#{'TC_PARALLEL_ID='+fork_identifier if index > 0} bundle exec rspec -r turnip/rspec -r turnip/capybara #{args} #{test_slices[index].join(' ')} > #{log_file}"
              `#{'TC_PARALLEL_ID='+fork_identifier if index > 0} bundle exec rspec -r turnip/rspec -r turnip/capybara #{args} #{test_slices[index].join(' ')} > #{log_file}`

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

        def db_options(db_config)
          "-u #{db_config['username']} #{db_config['password'].blank? ? '' : '-p'+db_config['password']} #{db_config['host'].blank? ? '' : '-h'+db_config['host']} #{db_config['port'].blank? ? '' : '-P'+db_config['port']} #{db_config['socket'].blank? ? '' : '--socket='+db_config['socket']}"
        end

        def clean_up_dbs(num, identifier, db_config)
          (num - 1).times do |i|
            db_name = "#{db_config['database']}#{identifier}#{i + 1}"
            begin
              puts "mysqladmin #{db_options(db_config)} -f drop #{db_name}"
              system("mysqladmin #{db_options(db_config)} -f drop #{db_name}")
            rescue => e
              puts e.message
              puts e.backtrace.join("\n\t")
            end
          end
        end

        def combine_failures(num, identifier)
          target = 'tmp/integration.failures'
          (num - 1).times do |i|
            # Files start from 1, not 0. Hence the i + 1
            from = "tmp/integration#{identifier}#{i + 1}.failures"
            begin
              if File.exist?(from)
                system("cat #{from} >> #{target}")
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

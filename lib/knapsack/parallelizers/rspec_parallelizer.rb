module Knapsack::Parallelizer
  class RSpecParallelizer < Knapsack::Parallelizer::Base
    class << self
      def test(test_slices, index, identifier, options)
        #sleep(index * 12)
        # For processes other than the very first one, fork_identifier is used
        # as the last portion of the database name and also part of the failure
        # log file names.
        fork_identifier = "#{identifier}#{index}"
        # Use time for the regular (not failure) log file names so that when running
        # it locally, it would not overwrite the previous log files
        log_file = "knapsack#{options[:time].to_i}_#{index}.log"
        run_cmd("#{'TC_PARALLEL_ID='+fork_identifier if index > 0} bundle exec rspec -r turnip/rspec -r turnip/capybara #{options[:args]} #{test_slices[index].join(' ')} > #{log_file}")
      ensure
        puts '**********************************'
        puts "Parallel testing #{index}/#{test_slices.length} finished"
        system("cat #{log_file}")
      end

      # Duplicating test databases for forks other than the first one, since the first fork uses
      # the main database (the one we are duplicating from, without the added identifier)
      def setup(num, identifier, options = {})
        db_config = YAML.load(ERB.new(File.read('config/database.yml')).result)['test']
        # Generate the integration db script that will be reloaded before every test
        run_cmd("RAILS_ENV=test bundle exec rake integration_test:setup_db")
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

      def clean_up(num, identifier, options = {})
        combine_failures(num, identifier)
        clean_up_dbs(num, identifier)
      end

      private

      def run_cmd(cmd)
        puts cmd
        system(cmd)
      end

      def db_options(db_config)
        "-u #{db_config['username']} #{db_config['password'].blank? ? '' : '-p'+db_config['password']} #{db_config['host'].blank? ? '' : '-h'+db_config['host']} #{db_config['port'].blank? ? '' : '-P'+db_config['port']} #{db_config['socket'].blank? ? '' : '--socket='+db_config['socket']}"
      end

      # Clean up the dupli
      def clean_up_dbs(num, identifier)
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

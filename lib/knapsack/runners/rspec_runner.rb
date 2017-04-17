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

        num_agents = ENV['NUM_AGENTS_PER_INSTANCE'] || 2
        num = (ncpu.to_f / (num_agents == 0 ? 2 : num_agents)).ceil
        if num > 1
          test_slices = allocator.split_tests(num)
          if test_slices.length > 1
            begin
              puts "Tests will be parallelized into #{test_slices.length} processes"
              Parallelizer.run(test_slices)
              exit(0)
            rescue => e
              puts e.message
              puts e.backtrace.join("\n\t")
              exit(1)
            end
          end
        end
        cmd = %Q[bundle exec rspec #{args} --default-path #{allocator.test_dir} -- #{allocator.stringify_node_tests} > single#{Time.now.to_i}.log]
        system(cmd)
        exit($?.exitstatus) unless $?.exitstatus.zero?
      end

      def self.ncpu
        #sysctl for OSX, nproc for linux
        RUBY_PLATFORM.include?('darwin') ? `sysctl -n hw.ncpu`.to_i : `nproc`.to_i
      rescue Errno::ENOENT
        1
      end
    end

    class Parallelizer
      class << self
        def run(test_slices)
          forks = test_slices.length
          # Prefix for the docker container name
          prefix = "mysql#{rand(1000000)}_"

          ports = start_dbs(forks, prefix)
          # Wait for services in the docker container to start
          sleep(45)

          run_tests(test_slices, prefix, ports)
        end

        private

        def start_dbs(num, prefix)
          ports = {}
          # Start docker containers (serially, docker seems to have problems with concurrency)
          num.times do |i|
            name = prefix + i.to_s
            # Start mysql and get the mapped port
            sh("docker run -d -p 3306 -e MYSQL_ROOT_PASSWORD=password --name #{name} mysql:5.7")
            ports[name] = `docker port #{name} 3306`.split(":").last.to_i
          end
          ports
        end

        def run_tests(test_slices, prefix, ports)
          forks = test_slices.length
          pids = []
          time = Time.now.to_i
          file_list = []
          forks.times do |i|
            pids << fork do
              sleep(i * 5)
              port = ports[prefix + i.to_s]
              mysql_opts = "-h127.0.0.1 -uroot -ppassword --port=#{port}"
              sh("mysqladmin #{mysql_opts} create coupa_test")
              sh("time mysql #{mysql_opts} coupa_test < testdb.sql")

              file_list << "knapsack#{time}_#{i}.log"
              sh("USING_CAPYBARA=true MYSQL_PORT=#{port} bundle exec rspec -r turnip/rspec -r turnip/capybara #{test_slices[i].join(' ')} > knapsack#{time}_#{i}.log")
              puts '******************'
              puts "Parallel testing #{i} finished"

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
          # Knapsack::LogCombiner.output(file_list)
          puts "Stopping docker containers"
          clean_up(forks, prefix)
        end

        def clean_up(num, prefix)
          dbs = ''
          num.times {|i| dbs += dbs + "#{prefix}#{i} " }
          sh("docker rm -f #{dbs}")
        ensure
          sh("docker volume prune -f")
        end
      end
    end

  end
end

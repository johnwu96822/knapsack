require 'knapsack'

namespace :knapsack do
  desc "This outputs remaining logs and cleans up additional databases generated during knapsack:rspec"
  task :cleanup do
    Knapsack::Parallelizer::RSpecParallelizer.clean_up
  end
end

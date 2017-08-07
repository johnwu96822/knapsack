module Knapsack::Util
  class << self

    def run_cmd(cmd)
      puts cmd if to_bool(ENV['VERBOSE'])
      system(cmd)
    end

    # Copied from coupa_development/spec/support/integration/shared_functions.rb
    def to_bool(x)
      return x if !!x == x
      return true if x =~ /^(true|t|yes|y|1)$/i
      return false if x =~ /^(false|f|no|n|0)$/i
      !x.nil?
    end

  end
end

describe Knapsack::Runners::RSpecRunner do
  describe '#max_process_count' do
    before { allow(Knapsack::Runners::RSpecRunner).to receive(:ncpu).and_return(8) }
    after do
      ENV['MAX_PROCESS_PER_AGENT'] = nil
      ENV['NUM_AGENTS_PER_INSTANCE'] = nil
    end
    subject { Knapsack::Runners::RSpecRunner.max_process_count }

    it { should eql 4 }

    describe 'MAX_PROCESS_PER_AGENT' do
      context 'max per agent is less than the calculated number' do
        before { ENV['MAX_PROCESS_PER_AGENT'] = '3' }

        it { should eql 3 }
      end

      context 'max per agent is more than the calculated number' do
        before { ENV['MAX_PROCESS_PER_AGENT'] = '5' }

        it { should eql 4 }

        context 'max per agent is 1' do
          before { ENV['MAX_PROCESS_PER_AGENT'] = '1' }

          it { should eql 1 }
        end
      end

      context 'max per agent is 0' do
        before { ENV['MAX_PROCESS_PER_AGENT'] = '0' }

        it { should eql 4 }
      end

      context 'max per agent is -1' do
        before { ENV['MAX_PROCESS_PER_AGENT'] = '-1' }

        it { should eql 4 }
      end
    end

    describe 'NUM_AGENTS_PER_INSTANCE' do
      before { ENV['NUM_AGENTS_PER_INSTANCE'] = '3' }

      it { should eql 3 }

      context 'number of agents is bigger than number of CPUs' do
        before { ENV['NUM_AGENTS_PER_INSTANCE'] = '10' }

        it { should eql 1 }
      end

      context 'number of agents is 1' do
        before { ENV['NUM_AGENTS_PER_INSTANCE'] = '1' }

        it { should eql 8 }
      end

      context 'number of agents is 0' do
        before { ENV['NUM_AGENTS_PER_INSTANCE'] = '0' }

        it { should eql 4 }
      end

      context 'number of agents is -1' do
        before { ENV['NUM_AGENTS_PER_INSTANCE'] = '-1' }

        it { should eql 4 }
      end
    end
  end
end

describe Knapsack::Parallelizer::Base do
  let(:slices) { [['f1.rb']] }

  describe '#run' do
    subject { Knapsack::Parallelizer::Base.run(slices) }

    it 'should not raise error' do
      expect(Process).not_to receive(:wait)
      expect(Knapsack::Parallelizer::Base).to receive(:test).once
      subject
    end

    context 'with multiple file slices' do
      let(:slices) { [['f1.rb'], ['f2.rb'], ['f3.rb']] }

      it 'should run multiple forks' do
        expect(Process).to receive(:wait).and_call_original.exactly(slices.length).times
        subject
      end

    end
  end
end

describe Knapsack::Allocator do
  let(:test_file_pattern) { nil }
  let(:args) do
    {
      ci_node_total: nil,
      ci_node_index: nil,
      test_file_pattern: test_file_pattern,
      report: nil
    }
  end
  let(:report_distributor) { instance_double(Knapsack::Distributors::ReportDistributor) }
  let(:leftover_distributor) { instance_double(Knapsack::Distributors::LeftoverDistributor) }
  let(:report_tests) { ['a_spec.rb', 'b_spec.rb'] }
  let(:leftover_tests) { ['c_spec.rb', 'd_spec.rb'] }
  let(:node_tests) { report_tests + leftover_tests }
  let(:allocator) { described_class.new(args) }

  before do
    expect(Knapsack::Distributors::ReportDistributor).to receive(:new).with(args).and_return(report_distributor)
    expect(Knapsack::Distributors::LeftoverDistributor).to receive(:new).with(args).and_return(leftover_distributor)
    allow(report_distributor).to receive(:tests_for_current_node).and_return(report_tests)
    allow(leftover_distributor).to receive(:tests_for_current_node).and_return(leftover_tests)
  end

  describe '#report_node_tests' do
    subject { allocator.report_node_tests }
    it { should eql report_tests }
  end

  describe '#leftover_node_tests' do
    subject { allocator.leftover_node_tests }
    it { should eql leftover_tests }
  end

  describe '#node_tests' do
    subject { allocator.node_tests }
    it { should eql node_tests }
  end

  describe '#stringify_node_tests' do
    subject { allocator.stringify_node_tests }
    it { should eql node_tests.join(' ') }
  end

  describe '#test_dir' do
    let(:test_file_pattern) { "test_dir/**/*_spec.rb" }

    subject { allocator.test_dir }

    before do
      expect(report_distributor).to receive(:test_file_pattern).and_return(test_file_pattern)
    end

    it { should eql 'test_dir/' }
  end

  describe '#split_tests' do
    let(:report_tests) { ['a_spec.rb', 'b_spec.rb', 'c_spec.rb', 'd_spec.rb'] }
    let(:leftover_tests) { ['e_spec.rb', 'f_spec.rb'] }

    context 'with splitting number less than 2' do
      it 'returns the original list wrapped in an array' do
        slices = allocator.split_tests(1)
        expect(slices.length).to eq(1)
        expect(slices[0]).to eq(allocator.node_tests)
      end
    end

    context 'with total number of files less than 5' do
      let(:report_tests) { ['a_spec.rb', 'b_spec.rb'] }

      it 'returns the original list wrapped in an array' do
        slices = allocator.split_tests(3)
        expect(slices.length).to eq(1)
        expect(slices[0]).to eq(allocator.node_tests)
      end
    end

    context 'with splitting number greater or equal to the number of files' do
      it 'returns an array with each element being one-element array with one file' do
        slices = allocator.split_tests(6)
        expect(slices.length).to eq(6)
        slices.each{ |slice| expect(slice.length).to eq(1) }
      end

      it 'returns an array with each element being one-element array with one file' do
        slices = allocator.split_tests(8)
        expect(slices.length).to eq(6)
        slices.each{ |slice| expect(slice.length).to eq(1) }
      end
    end

    context 'with splitting number less than the number of files' do
      it 'evenly distributes the number of files for each slice' do
        slices = allocator.split_tests(2)
        expect(slices.length).to eq(2)
        slices.each{ |slice| expect(slice.length).to eq(3) }

        slices = allocator.split_tests(3)
        expect(slices.length).to eq(3)
        slices.each{ |slice| expect(slice.length).to eq(2) }
      end

      context 'and remaining files after even split' do
        let(:leftover_tests) { ['e_spec.rb', 'f_spec.rb', 'g_spec.rb'] }

        it 'evenly distributes remaining files starting from the beginning slice' do
          slices = allocator.split_tests(4)
          expect(slices.length).to eq(4)
          puts slices.inspect
          expect(slices[0].length).to eq(2)
          expect(slices[1].length).to eq(2)
          expect(slices[2].length).to eq(2)
          expect(slices[3].length).to eq(1)
        end
      end

      context 'and larger number of files' do
        let(:leftover_tests) do
          tests = []
          96.times{|i| tests << "#{i}_spec.rb" }
          tests
        end

        it 'evenly distributes remaining files starting from the beginning slice' do
          slices = allocator.split_tests(5)
          expect(slices.length).to eq(5)
          slices.each{ |slice| expect(slice.length).to eq(20) }

          slices = allocator.split_tests(6)
          expect(slices.length).to eq(6)
          expect(slices[0].length).to eq(17)
          expect(slices[1].length).to eq(17)
          expect(slices[2].length).to eq(17)
          expect(slices[3].length).to eq(17)
          expect(slices[4].length).to eq(16)
          expect(slices[5].length).to eq(16)

          slices = allocator.split_tests(51)
          expect(slices.length).to eq(51)
          slices.each_with_index do |slice, index|
            if index < 49
              expect(slice.length).to eq(2)
            else
              expect(slice.length).to eq(1)
            end
          end
        end
      end
    end
  end
end

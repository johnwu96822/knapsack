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

  describe '#distribute_files' do
    let(:report_tests) { ['a_spec.rb', 'b_spec.rb', 'c_spec.rb', 'd_spec.rb'] }
    let(:leftover_tests) { ['e_spec.rb', 'f_spec.rb'] }

    context 'with splitting number less than 2' do
      it 'returns the original list wrapped in an array' do
        slices = allocator.distribute_files(1)
        expect(slices.length).to eq(1)
        expect(slices[0]).to eq(allocator.node_tests)
      end
    end

    context 'with total number of files less or equal to PARALLEL_THRESHOLD' do
      let(:report_tests) { [] }

      it 'returns the original list wrapped in an array' do
        slices = allocator.distribute_files(3)
        expect(slices.length).to eq(1)
        expect(slices[0]).to eq(allocator.node_tests)
      end
    end

    context 'with splitting number greater or equal to the number of files' do
      it 'returns an array with evenly distributed file slices, each with at least 2 files' do
        slices = allocator.distribute_files(8)
        expect(slices.length).to eq(6)
        expect(slices[0]).to eq(['a_spec.rb'])
        expect(slices[1]).to eq(['b_spec.rb'])
        expect(slices[2]).to eq(['c_spec.rb'])
        expect(slices[3]).to eq(['d_spec.rb'])
        expect(slices[4]).to eq(['e_spec.rb'])
        expect(slices[5]).to eq(['f_spec.rb'])
      end
    end

    context 'with splitting number less than the number of files' do
      it 'evenly distributes files in original order for each slice' do
        slices = allocator.distribute_files(2)
        expect(slices.length).to eq(2)
        expect(slices[0]).to eq(['a_spec.rb', 'b_spec.rb', 'c_spec.rb'])
        expect(slices[1]).to eq(['d_spec.rb', 'e_spec.rb', 'f_spec.rb'])

        slices = allocator.distribute_files(3)
        expect(slices.length).to eq(3)
        expect(slices[0]).to eq(['a_spec.rb', 'b_spec.rb'])
        expect(slices[1]).to eq(['c_spec.rb', 'd_spec.rb'])
        expect(slices[2]).to eq(['e_spec.rb', 'f_spec.rb'])
      end

      context 'and remaining files after even split' do
        let(:leftover_tests) { ['e_spec.rb', 'f_spec.rb', 'g_spec.rb'] }

        it 'evenly distributes in original order for each slice' do
          slices = allocator.distribute_files(4)
          expect(slices.length).to eq(4)
          expect(slices[0]).to eq(['a_spec.rb', 'b_spec.rb'])
          expect(slices[1]).to eq(['c_spec.rb', 'd_spec.rb'])
          expect(slices[2]).to eq(['e_spec.rb', 'f_spec.rb'])
          expect(slices[3]).to eq(['g_spec.rb'])

          slices = allocator.distribute_files(2)
          expect(slices.length).to eq(2)
          expect(slices[0]).to eq(['a_spec.rb', 'b_spec.rb', 'c_spec.rb', 'd_spec.rb'])
          expect(slices[1]).to eq(['e_spec.rb', 'f_spec.rb', 'g_spec.rb'])
        end
      end

      context 'and larger number of files' do
        let(:leftover_tests) do
          tests = []
          96.times{|i| tests << "#{i}_spec.rb" }
          tests
        end

        it 'evenly distributes files' do
          slices = allocator.distribute_files(5)
          expect(slices.length).to eq(5)
          slices.each{ |slice| expect(slice.length).to eq(20) }

          slices = allocator.distribute_files(6)
          expect(slices.length).to eq(6)
          expect(slices[0].length).to eq(17)
          expect(slices[1].length).to eq(17)
          expect(slices[2].length).to eq(17)
          expect(slices[3].length).to eq(17)
          expect(slices[4].length).to eq(16)
          expect(slices[5].length).to eq(16)

          slices = allocator.distribute_files(51)
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

  describe '#determine_number_of_processes' do
    it 'determines the number of processes to use based on number of files provided' do
      data = [
        # [file size, no of processes, expected result]
        [100, 2, 2],
        [99, 2, 2],

        [5, 10, 5],
        [4, 10, 4],
        [3, 10, 3],

        [5, 2, 2],
        [4, 2, 2],
        [3, 2, 2],

        [5, 3, 3],
        [4, 3, 3],
        [3, 3, 3],
        [2, 3, 1],
        [1, 3, 1],

        [10, 4, 4],
        [9, 4, 4],
        [8, 4, 4],
        [7, 4, 4],
        [6, 4, 4],
        [5, 4, 4],
        [4, 4, 4],
        [3, 4, 3],
        [2, 4, 1],
        [1, 4, 1],

        [10, 8, 8],
        [9, 8, 8],
        [8, 8, 8],
        [7, 8, 7],
        [6, 8, 6],
        [5, 8, 5],
        [4, 8, 4],
        [3, 8, 3],
        [2, 8, 1],
        [1, 8, 1]
      ]

      data.each do |d|
        expect(allocator.determine_number_of_processes(d[0], d[1])).to eq(d[2])
      end
    end
  end
end

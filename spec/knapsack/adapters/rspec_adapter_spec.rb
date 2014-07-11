describe Knapsack::Adapters::RspecAdapter do
  before do
    expect(::RSpec).to receive(:configure)
  end

  describe '#bind_time_tracker' do
    it do
      expect {
        subject.bind_time_tracker
      }.not_to raise_error
    end
  end

  describe '#bind_report_generator' do
    it do
      expect {
        subject.bind_report_generator
      }.not_to raise_error
    end
  end

  describe '#bind_time_offset_warning' do
    it do
      expect {
        subject.bind_time_offset_warning
      }.not_to raise_error
    end
  end
end

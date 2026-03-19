require 'spec_helper'

RSpec.describe RailsLogViewer::LogParser do
  describe '.extract_timestamp' do
    it 'parses Ruby Logger format' do
      line = 'I, [2026-03-19T10:00:00.000000 #1234]  INFO -- : test'
      ts = described_class.extract_timestamp(line)

      expect(ts).to be_a(Time)
      expect(ts.year).to eq(2026)
      expect(ts.hour).to eq(10)
    end

    it 'parses ISO8601 timestamps' do
      line = '2026-03-19T10:00:00 INFO test message'
      ts = described_class.extract_timestamp(line)

      expect(ts).to be_a(Time)
      expect(ts.day).to eq(19)
    end

    it 'parses space-separated datetime' do
      line = '2026-03-19 10:00:00 INFO test message'
      ts = described_class.extract_timestamp(line)

      expect(ts).to be_a(Time)
    end

    it 'returns nil for lines without timestamps' do
      expect(described_class.extract_timestamp('just a plain line')).to be_nil
    end
  end

  describe '.extract_severity' do
    it 'parses Ruby Logger prefix' do
      expect(described_class.extract_severity('I, [2026-03-19T10:00:00.000000 #1234]  INFO')).to eq('INFO')
      expect(described_class.extract_severity('E, [2026-03-19T10:00:00.000000 #1234]  ERROR')).to eq('ERROR')
      expect(described_class.extract_severity('W, [2026-03-19T10:00:00.000000 #1234]  WARN')).to eq('WARN')
      expect(described_class.extract_severity('D, [2026-03-19T10:00:00.000000 #1234]  DEBUG')).to eq('DEBUG')
      expect(described_class.extract_severity('F, [2026-03-19T10:00:00.000000 #1234]  FATAL')).to eq('FATAL')
    end

    it 'parses standalone severity words' do
      expect(described_class.extract_severity('2026-03-19 ERROR something broke')).to eq('ERROR')
      expect(described_class.extract_severity('INFO: starting up')).to eq('INFO')
    end

    it 'normalizes WARNING to WARN' do
      expect(described_class.extract_severity('WARNING: disk space low')).to eq('WARN')
    end

    it 'returns nil when no severity found' do
      expect(described_class.extract_severity('just a plain line')).to be_nil
    end
  end

  describe '.parse' do
    it 'returns a hash with message, timestamp, and severity' do
      line = 'I, [2026-03-19T10:00:00.000000 #1234]  INFO -- : Hello'
      result = described_class.parse(line)

      expect(result[:message]).to eq(line)
      expect(result[:timestamp]).to be_a(Time)
      expect(result[:severity]).to eq('INFO')
    end

    it 'uses fallback_time when no timestamp in line' do
      fallback = Time.new(2026, 3, 19, 10, 0, 0)
      result = described_class.parse('  continuation line', fallback_time: fallback)

      expect(result[:timestamp]).to eq(fallback)
    end
  end
end

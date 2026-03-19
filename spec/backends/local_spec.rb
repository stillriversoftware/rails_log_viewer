require 'spec_helper'
require 'tmpdir'

RSpec.describe RailsLogViewer::Backends::Local do
  let(:fixture_path) { File.expand_path('../fixtures/test.log', __dir__) }
  let(:backend) { described_class.new(log_path: fixture_path) }

  describe '#read' do
    it 'returns the last N lines from the file' do
      result = backend.read(lines: 5)

      expect(result[:lines].length).to eq(5)
      expect(result[:lines].last).to include('Line number 20')
      expect(result[:lines].first).to include('Line number 16')
      expect(result[:total_estimated]).to eq(20)
      expect(result[:truncated]).to be true
    end

    it 'returns all lines when requesting more than the file contains' do
      result = backend.read(lines: 100)

      expect(result[:lines].length).to eq(20)
      expect(result[:lines].first).to include('Line number 1')
      expect(result[:lines].last).to include('Line number 20')
      expect(result[:truncated]).to be false
    end

    context 'with offset-based pagination' do
      it 'skips N lines from the end' do
        result = backend.read(lines: 5, offset: 5)

        expect(result[:lines].length).to eq(5)
        expect(result[:lines].last).to include('Line number 15')
        expect(result[:lines].first).to include('Line number 11')
      end

      it 'returns fewer lines when offset nears the start' do
        result = backend.read(lines: 5, offset: 17)

        expect(result[:lines].length).to eq(3)
        expect(result[:lines].first).to include('Line number 1')
        expect(result[:lines].last).to include('Line number 3')
      end
    end
  end

  describe '#search' do
    it 'finds lines matching a plain string' do
      result = backend.search(pattern: 'ERROR')

      expect(result[:lines]).to all(include('ERROR'))
      expect(result[:lines].length).to eq(10)
    end

    it 'finds lines matching a Regexp' do
      result = backend.search(pattern: /Line number (1|20)\b/)

      expect(result[:lines].length).to eq(2)
      expect(result[:lines].first).to include('Line number 1')
      expect(result[:lines].last).to include('Line number 20')
    end

    it 'limits results to the requested line count' do
      result = backend.search(pattern: 'ERROR', lines: 3)

      expect(result[:lines].length).to eq(3)
      expect(result[:truncated]).to be true
    end

    it 'returns results ordered from earliest to latest' do
      result = backend.search(pattern: 'ERROR', lines: 3)

      numbers = result[:lines].map { |l| l[/Line number (\d+)/, 1].to_i }
      expect(numbers).to eq(numbers.sort)
    end
  end

  describe 'redaction' do
    it 'replaces matches from configured redact_patterns' do
      RailsLogViewer.configure do |c|
        c.redact_patterns = [/token=\S+/, /user_email=\S+/]
      end

      result = backend.read(lines: 1)
      line = result[:lines].first

      expect(line).to include('[REDACTED]')
      expect(line).not_to include('secret_abc_')
      expect(line).not_to include('@example.com')
    end

    it 'applies redaction to search results' do
      RailsLogViewer.configure do |c|
        c.redact_patterns = [/token=\S+/]
      end

      result = backend.search(pattern: 'ERROR', lines: 1)
      line = result[:lines].first

      expect(line).to include('[REDACTED]')
      expect(line).not_to include('secret_abc_')
    end

    it 'leaves lines unchanged when no patterns are configured' do
      result = backend.read(lines: 1)

      expect(result[:lines].first).to include('secret_abc_')
    end
  end

  describe 'error handling' do
    it 'returns an error hash when the file does not exist' do
      backend = described_class.new(log_path: '/tmp/nonexistent_log_file.log')
      result = backend.read(lines: 10)

      expect(result[:error]).to eq('Log file not found')
      expect(result[:path]).to eq('/tmp/nonexistent_log_file.log')
    end

    it 'returns an error hash for search on a missing file' do
      backend = described_class.new(log_path: '/tmp/nonexistent_log_file.log')
      result = backend.search(pattern: 'test')

      expect(result[:error]).to eq('Log file not found')
    end

    it 'returns an error hash when the file is not readable' do
      unreadable = File.join(Dir.tmpdir, "rlv_unreadable_#{Process.pid}.log")
      File.write(unreadable, "test line\n")
      File.chmod(0o000, unreadable)

      backend = described_class.new(log_path: unreadable)
      result = backend.read(lines: 10)

      expect(result[:error]).to eq('Permission denied')
    ensure
      File.chmod(0o644, unreadable) if File.exist?(unreadable)
      File.delete(unreadable) if File.exist?(unreadable)
    end
  end
end

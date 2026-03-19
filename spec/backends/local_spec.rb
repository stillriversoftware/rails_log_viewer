require 'spec_helper'
require 'tmpdir'

RSpec.describe RailsLogViewer::Backends::Local do
  let(:fixture_path) { File.expand_path('../fixtures/test.log', __dir__) }
  let(:backend) { described_class.new(log_path: fixture_path) }

  describe '#query' do
    it 'returns lines from the end of the file by default' do
      result = backend.query(limit: 5)

      expect(result[:lines].length).to eq(5)
      expect(result[:lines].last[:message]).to include('RoutingError')
      expect(result[:lines].first[:message]).to include('Completed 200 OK in 55ms')
    end

    it 'returns all lines when limit exceeds file size' do
      result = backend.query(limit: 100)

      expect(result[:lines].length).to eq(20)
      expect(result[:lines].first[:message]).to include('Started GET "/users"')
      expect(result[:lines].last[:message]).to include('RoutingError')
    end

    it 'parses timestamps from log lines' do
      result = backend.query(limit: 1)

      expect(result[:lines].first[:timestamp]).to be_a(Time)
    end

    it 'parses severity from log lines' do
      result = backend.query(limit: 20)

      severities = result[:lines].map { |l| l[:severity] }.compact.uniq
      expect(severities).to include('INFO', 'ERROR', 'WARN', 'DEBUG')
    end

    context 'cursor-based pagination' do
      it 'returns cursors for further navigation' do
        result = backend.query(limit: 5)

        expect(result[:cursors][:older]).to be_a(String)
        expect(result[:cursors][:older]).to start_with('b:')
      end

      it 'loads older logs using the older cursor' do
        first_page = backend.query(limit: 5)
        second_page = backend.query(limit: 5, cursor: first_page[:cursors][:older], direction: :older)

        first_messages = first_page[:lines].map { |l| l[:message] }
        second_messages = second_page[:lines].map { |l| l[:message] }
        expect(first_messages & second_messages).to be_empty
      end

      it 'loads newer logs using the newer cursor' do
        first_page = backend.query(limit: 10)
        older_cursor = first_page[:cursors][:older]

        older_page = backend.query(limit: 5, cursor: older_cursor, direction: :older)
        newer_page = backend.query(limit: 5, cursor: older_page[:cursors][:newer], direction: :newer)

        expect(newer_page[:lines]).not_to be_empty
      end
    end

    context 'time filtering' do
      it 'filters lines within a time range' do
        start_time = Time.new(2026, 3, 19, 10, 0, 3)
        end_time = Time.new(2026, 3, 19, 10, 0, 4)

        result = backend.query(start_time: start_time, end_time: end_time, limit: 100)

        result[:lines].each do |line|
          expect(line[:timestamp]).to be >= start_time
          expect(line[:timestamp]).to be <= end_time
        end
      end

      it 'returns no lines for a time range with no data' do
        start_time = Time.new(2020, 1, 1)
        end_time = Time.new(2020, 1, 2)

        result = backend.query(start_time: start_time, end_time: end_time, limit: 100)

        expect(result[:lines]).to be_empty
      end
    end

    context 'severity filtering' do
      it 'returns only lines matching the requested severity' do
        result = backend.query(severity: ['ERROR'], limit: 100)

        expect(result[:lines]).not_to be_empty
        result[:lines].each do |line|
          expect(line[:severity]).to eq('ERROR')
        end
      end

      it 'supports multiple severity levels' do
        result = backend.query(severity: ['ERROR', 'FATAL'], limit: 100)

        severities = result[:lines].map { |l| l[:severity] }.uniq
        expect(severities).to all(be_in(['ERROR', 'FATAL']))
      end
    end

    context 'search' do
      it 'returns only lines matching the search text' do
        result = backend.query(search: 'ConnectionBad', limit: 100)

        expect(result[:lines].length).to eq(1)
        expect(result[:lines].first[:message]).to include('ConnectionBad')
      end

      it 'is case-insensitive' do
        result = backend.query(search: 'connectionbad', limit: 100)

        expect(result[:lines].length).to eq(1)
      end

      it 'composes with severity filtering' do
        result = backend.query(search: 'Completed', severity: ['INFO'], limit: 100)

        expect(result[:lines]).not_to be_empty
        result[:lines].each do |line|
          expect(line[:message]).to include('Completed')
          expect(line[:severity]).to eq('INFO')
        end
      end
    end

    context 'redaction' do
      it 'redacts configured patterns' do
        RailsLogViewer.configure do |c|
          c.redact_patterns = [/token=\S+/, /user_email=\S+/]
        end

        result = backend.query(search: 'crashed', limit: 1)

        expect(result[:lines].first[:message]).to include('[REDACTED]')
        expect(result[:lines].first[:message]).not_to include('secret_abc_123')
        expect(result[:lines].first[:message]).not_to include('admin@example.com')
      end
    end

    context 'error handling' do
      it 'returns an error hash when the file does not exist' do
        backend = described_class.new(log_path: '/tmp/nonexistent_log_file.log')
        result = backend.query(limit: 10)

        expect(result[:error]).to eq('Log file not found')
      end

      it 'returns an error hash when the file is not readable' do
        unreadable = File.join(Dir.tmpdir, "rlv_unreadable_#{Process.pid}.log")
        File.write(unreadable, "test\n")
        File.chmod(0o000, unreadable)

        backend = described_class.new(log_path: unreadable)
        result = backend.query(limit: 10)

        expect(result[:error]).to eq('Permission denied')
      ensure
        File.chmod(0o644, unreadable) if File.exist?(unreadable)
        File.delete(unreadable) if File.exist?(unreadable)
      end
    end
  end
end

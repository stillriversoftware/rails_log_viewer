require 'spec_helper'
require 'aws-sdk-s3'

RSpec.describe RailsLogViewer::Backends::S3 do
  let(:client) { Aws::S3::Client.new(stub_responses: true) }
  let(:backend) do
    described_class.new(
      bucket: 'my-logs-bucket',
      prefix: 'production/logs/',
      region: 'us-east-1',
      aws_client: client
    )
  end

  let(:log_content) do
    [
      'I, [2026-03-19T10:00:00.000000 #1234]  INFO -- : Started GET "/users" for 127.0.0.1',
      'I, [2026-03-19T10:00:00.050000 #1234]  INFO -- : Completed 200 OK in 50ms',
      'E, [2026-03-19T10:00:01.000000 #1234]  ERROR -- : PG::ConnectionBad: connection refused',
      'W, [2026-03-19T10:00:02.000000 #1234]  WARN -- : Cache miss for key user_list',
      'I, [2026-03-19T10:00:03.000000 #1234]  INFO -- : Started GET "/health" for 10.0.0.1',
      'D, [2026-03-19T10:00:04.000000 #1234]  DEBUG -- : SQL query (0.5ms)',
      'I, [2026-03-19T10:00:05.000000 #1234]  INFO -- : Completed 200 OK in 2ms password=secret123',
      'E, [2026-03-19T10:00:06.000000 #1234]  ERROR -- : ActionController::RoutingError (No route)',
    ].join("\n") + "\n"
  end

  let(:now) { Time.new(2026, 3, 19, 12, 0, 0) }

  before do
    client.stub_responses(:list_objects_v2, {
      contents: [
        { key: 'production/logs/app-2026-03-19.log', size: 5000, last_modified: Time.new(2026, 3, 19) },
        { key: 'production/logs/app-2026-03-18.log', size: 4500, last_modified: Time.new(2026, 3, 18) },
        { key: 'production/logs/app-2026-03-17.log.gz', size: 1200, last_modified: Time.new(2026, 3, 17) },
      ]
    })

    client.stub_responses(:get_object, { body: StringIO.new(log_content) })
  end

  describe '#files' do
    it 'returns log files sorted by most recent first' do
      result = backend.files

      expect(result.length).to eq(3)
      expect(result.first[:key]).to include('2026-03-19')
      expect(result.last[:key]).to include('2026-03-17')
    end

    it 'includes file metadata' do
      result = backend.files

      file = result.first
      expect(file[:key]).to be_a(String)
      expect(file[:size]).to be_a(Integer)
      expect(file[:last_modified]).to be_a(Time)
      expect(file[:name]).to eq('app-2026-03-19.log')
    end

    it 'respects the limit parameter' do
      result = backend.files(limit: 1)

      expect(result.length).to eq(1)
    end

    it 'filters out non-log files' do
      client.stub_responses(:list_objects_v2, {
        contents: [
          { key: 'production/logs/app.log', size: 100, last_modified: now },
          { key: 'production/logs/readme.md', size: 50, last_modified: now },
          { key: 'production/logs/', size: 0, last_modified: now },
          { key: 'production/logs/app.log.gz', size: 80, last_modified: now },
        ]
      })

      result = backend.files
      keys = result.map { |f| f[:key] }

      expect(keys).to include('production/logs/app.log')
      expect(keys).to include('production/logs/app.log.gz')
      expect(keys).not_to include('production/logs/readme.md')
      expect(keys).not_to include('production/logs/')
    end

    it 'returns an error hash on service failure' do
      client.stub_responses(:list_objects_v2, 'NoSuchBucket')

      result = backend.files

      expect(result[:error]).to eq('S3 service error')
    end
  end

  describe '#query' do
    context 'with a specific file_key' do
      it 'returns parsed log lines' do
        result = backend.query(file_key: 'production/logs/app-2026-03-19.log', limit: 100)

        expect(result[:lines].length).to eq(8)
        expect(result[:lines].first[:message]).to include('Started GET "/users"')
        expect(result[:lines].first[:timestamp]).to be_a(Time)
        expect(result[:lines].first[:severity]).to eq('INFO')
      end

      it 'limits results' do
        result = backend.query(file_key: 'production/logs/app-2026-03-19.log', limit: 3)

        expect(result[:lines].length).to eq(3)
      end

      it 'returns cursors for pagination' do
        result = backend.query(file_key: 'production/logs/app-2026-03-19.log', limit: 3)

        expect(result[:cursors][:older]).to be_a(String)
        expect(result[:cursors][:older]).to start_with('s3:')
        expect(result[:cursors][:newer]).to start_with('s3:')
      end

      it 'includes the file key in the response' do
        result = backend.query(file_key: 'production/logs/app-2026-03-19.log', limit: 3)

        expect(result[:file]).to eq('production/logs/app-2026-03-19.log')
      end
    end

    context 'cursor-based pagination' do
      it 'loads older lines using the older cursor' do
        first_page = backend.query(file_key: 'production/logs/app-2026-03-19.log', limit: 4)
        second_page = backend.query(file_key: 'production/logs/app-2026-03-19.log', limit: 4, cursor: first_page[:cursors][:older], direction: :older)

        first_messages = first_page[:lines].map { |l| l[:message] }
        second_messages = second_page[:lines].map { |l| l[:message] }
        expect(first_messages & second_messages).to be_empty
      end

      it 'loads newer lines using the newer cursor' do
        first_page = backend.query(file_key: 'production/logs/app-2026-03-19.log', limit: 4)
        newer_cursor = first_page[:cursors][:older]

        older_page = backend.query(file_key: 'production/logs/app-2026-03-19.log', limit: 4, cursor: newer_cursor, direction: :older)
        newer_page = backend.query(file_key: 'production/logs/app-2026-03-19.log', limit: 4, cursor: older_page[:cursors][:newer], direction: :newer)

        expect(newer_page[:lines]).not_to be_empty
      end
    end

    context 'filtering' do
      it 'filters by severity' do
        result = backend.query(file_key: 'production/logs/app-2026-03-19.log', severity: ['ERROR'], limit: 100)

        expect(result[:lines]).not_to be_empty
        result[:lines].each do |line|
          expect(line[:severity]).to eq('ERROR')
        end
      end

      it 'filters by search text' do
        result = backend.query(file_key: 'production/logs/app-2026-03-19.log', search: 'ConnectionBad', limit: 100)

        expect(result[:lines].length).to eq(1)
        expect(result[:lines].first[:message]).to include('ConnectionBad')
      end

      it 'filters by time range' do
        start_time = Time.new(2026, 3, 19, 10, 0, 2)
        end_time = Time.new(2026, 3, 19, 10, 0, 4)

        result = backend.query(file_key: 'production/logs/app-2026-03-19.log', start_time: start_time, end_time: end_time, limit: 100)

        result[:lines].each do |line|
          expect(line[:timestamp]).to be >= start_time
          expect(line[:timestamp]).to be <= end_time
        end
      end

      it 'composes search with severity' do
        result = backend.query(file_key: 'production/logs/app-2026-03-19.log', search: 'Completed', severity: ['INFO'], limit: 100)

        expect(result[:lines]).not_to be_empty
        result[:lines].each do |line|
          expect(line[:message]).to include('Completed')
          expect(line[:severity]).to eq('INFO')
        end
      end
    end

    context 'gzip handling' do
      it 'decompresses .gz files transparently' do
        gz_buffer = StringIO.new
        gz = Zlib::GzipWriter.new(gz_buffer)
        gz.write(log_content)
        gz.close

        client.stub_responses(:get_object, { body: StringIO.new(gz_buffer.string) })

        result = backend.query(file_key: 'production/logs/app-2026-03-17.log.gz', limit: 100)

        expect(result[:lines].length).to eq(8)
        expect(result[:lines].first[:message]).to include('Started GET')
      end
    end

    context 'without file_key' do
      it 'selects the most relevant file based on time range' do
        result = backend.query(end_time: Time.new(2026, 3, 19, 12, 0, 0), limit: 3)

        expect(result[:lines]).not_to be_empty
      end

      it 'returns empty result when no files exist' do
        client.stub_responses(:list_objects_v2, { contents: [] })

        result = backend.query(limit: 10)

        expect(result[:lines]).to be_empty
      end
    end

    context 'redaction' do
      it 'applies default redaction patterns' do
        result = backend.query(file_key: 'production/logs/app-2026-03-19.log', search: 'password', limit: 100)

        matching = result[:lines].select { |l| l[:message].include?('[REDACTED]') }
        expect(matching).not_to be_empty
        matching.each do |line|
          expect(line[:message]).not_to include('secret123')
        end
      end
    end

    context 'error handling' do
      it 'returns an error hash when file is not found' do
        client.stub_responses(:get_object, 'NoSuchKey')

        result = backend.query(file_key: 'nonexistent.log', limit: 10)

        expect(result[:error]).to eq('File not found')
      end

      it 'returns an error hash on service failure' do
        client.stub_responses(:get_object, 'InternalError')

        result = backend.query(file_key: 'some.log', limit: 10)

        expect(result[:error]).to eq('S3 service error')
      end
    end
  end

  describe 'credential errors' do
    let(:failing_client) do
      c = Aws::S3::Client.new(stub_responses: true)
      c.stub_responses(:list_objects_v2, Aws::Errors::MissingCredentialsError.new('no creds'))
      c.stub_responses(:get_object, Aws::Errors::MissingCredentialsError.new('no creds'))
      c
    end

    let(:failing_backend) do
      described_class.new(
        bucket: 'my-logs-bucket',
        region: 'us-east-1',
        aws_client: failing_client
      )
    end

    it 'returns a credential error from files' do
      result = failing_backend.files

      expect(result[:error]).to eq('AWS credentials missing')
    end

    it 'returns a credential error from query' do
      result = failing_backend.query(file_key: 'some.log', limit: 10)

      expect(result[:error]).to eq('AWS credentials missing')
    end
  end
end

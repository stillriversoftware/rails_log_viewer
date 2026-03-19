require 'spec_helper'
require 'aws-sdk-cloudwatchlogs'

RSpec.describe RailsLogViewer::Backends::Cloudwatch do
  let(:client) { Aws::CloudWatchLogs::Client.new(stub_responses: true) }
  let(:backend) do
    described_class.new(
      log_group: '/app/production',
      log_stream_prefix: 'web/',
      region: 'us-east-1',
      aws_client: client
    )
  end

  describe '#streams' do
    it 'returns log stream names ordered by most recent' do
      client.stub_responses(:describe_log_streams, {
        log_streams: [
          { log_stream_name: 'web/host-3', last_event_timestamp: 3000 },
          { log_stream_name: 'web/host-2', last_event_timestamp: 2000 },
          { log_stream_name: 'web/host-1', last_event_timestamp: 1000 }
        ]
      })

      result = backend.streams(limit: 3)

      expect(result).to eq(['web/host-3', 'web/host-2', 'web/host-1'])
    end

    it 'respects the limit parameter' do
      client.stub_responses(:describe_log_streams, {
        log_streams: [
          { log_stream_name: 'web/host-1', last_event_timestamp: 1000 }
        ]
      })

      result = backend.streams(limit: 1)

      expect(result.length).to eq(1)
    end

    it 'returns an error hash on service failure' do
      client.stub_responses(:describe_log_streams, 'ResourceNotFoundException')

      result = backend.streams

      expect(result[:error]).to eq('CloudWatch service error')
    end
  end

  describe '#read' do
    it 'returns log events from the specified stream' do
      now_ms = (Time.now.to_f * 1000).to_i
      client.stub_responses(:get_log_events, [
        {
          events: [
            { timestamp: now_ms - 2000, message: 'First log line', ingestion_time: now_ms },
            { timestamp: now_ms - 1000, message: 'Second log line', ingestion_time: now_ms },
            { timestamp: now_ms, message: 'Third log line', ingestion_time: now_ms }
          ],
          next_forward_token: 'token-a'
        },
        {
          events: [],
          next_forward_token: 'token-a'
        }
      ])

      result = backend.read(stream_name: 'web/host-1', lines: 10)

      expect(result[:lines].length).to eq(3)
      expect(result[:lines].first[:message]).to eq('First log line')
      expect(result[:lines].last[:message]).to eq('Third log line')
      expect(result[:stream]).to eq('web/host-1')
    end

    it 'converts timestamps to Time objects' do
      fixed_ms = 1_700_000_000_000
      client.stub_responses(:get_log_events, {
        events: [
          { timestamp: fixed_ms, message: 'test', ingestion_time: fixed_ms }
        ],
        next_forward_token: 'done'
      })

      result = backend.read(stream_name: 'web/host-1', lines: 10)

      expect(result[:lines].first[:timestamp]).to be_a(Time)
      expect(result[:lines].first[:timestamp]).to eq(Time.at(1_700_000_000))
    end

    it 'limits results to the requested line count' do
      now_ms = (Time.now.to_f * 1000).to_i
      events = 10.times.map do |i|
        { timestamp: now_ms + i, message: "Line #{i}", ingestion_time: now_ms }
      end
      client.stub_responses(:get_log_events, {
        events: events,
        next_forward_token: 'token-b'
      })

      result = backend.read(stream_name: 'web/host-1', lines: 5)

      expect(result[:lines].length).to eq(5)
      expect(result[:lines].last[:message]).to eq('Line 9')
      expect(result[:has_more]).to be true
    end

    it 'returns an error hash on service failure' do
      client.stub_responses(:get_log_events, 'ResourceNotFoundException')

      result = backend.read(stream_name: 'web/host-1', lines: 10)

      expect(result[:error]).to eq('CloudWatch service error')
    end
  end

  describe '#search' do
    it 'returns filtered events matching the pattern' do
      now_ms = (Time.now.to_f * 1000).to_i
      client.stub_responses(:filter_log_events, {
        events: [
          { timestamp: now_ms, message: 'ERROR something broke', log_stream_name: 'web/host-1', event_id: '1' },
          { timestamp: now_ms + 1000, message: 'ERROR another failure', log_stream_name: 'web/host-2', event_id: '2' }
        ],
        next_token: nil
      })

      result = backend.search(pattern: 'ERROR', hours_back: 2)

      expect(result[:lines].length).to eq(2)
      expect(result[:lines].first[:message]).to include('ERROR')
      expect(result[:lines].last[:stream]).to eq('web/host-2')
    end

    it 'includes the stream name on each entry' do
      now_ms = (Time.now.to_f * 1000).to_i
      client.stub_responses(:filter_log_events, {
        events: [
          { timestamp: now_ms, message: 'test', log_stream_name: 'web/host-5', event_id: '1' }
        ],
        next_token: nil
      })

      result = backend.search(pattern: 'test')
      expect(result[:lines].first[:stream]).to eq('web/host-5')
    end

    it 'returns an error hash on service failure' do
      client.stub_responses(:filter_log_events, 'ResourceNotFoundException')

      result = backend.search(pattern: 'ERROR')

      expect(result[:error]).to eq('CloudWatch service error')
    end
  end

  describe 'redaction' do
    it 'redacts configured patterns from read results' do
      RailsLogViewer.configure do |c|
        c.redact_patterns = [/secret_token=\S+/]
      end

      now_ms = (Time.now.to_f * 1000).to_i
      client.stub_responses(:get_log_events, {
        events: [
          { timestamp: now_ms, message: 'Login secret_token=abc123 completed', ingestion_time: now_ms }
        ],
        next_forward_token: 'done'
      })

      result = backend.read(stream_name: 'web/host-1', lines: 10)

      expect(result[:lines].first[:message]).to eq('Login [REDACTED] completed')
      expect(result[:lines].first[:message]).not_to include('abc123')
    end

    it 'redacts configured patterns from search results' do
      RailsLogViewer.configure do |c|
        c.redact_patterns = [/password=\S+/]
      end

      now_ms = (Time.now.to_f * 1000).to_i
      client.stub_responses(:filter_log_events, {
        events: [
          { timestamp: now_ms, message: 'Auth password=hunter2 failed', log_stream_name: 'web/host-1', event_id: '1' }
        ],
        next_token: nil
      })

      result = backend.search(pattern: 'Auth')

      expect(result[:lines].first[:message]).to eq('Auth [REDACTED] failed')
    end
  end

  describe 'credential errors' do
    let(:failing_client) do
      client = Aws::CloudWatchLogs::Client.new(stub_responses: true)
      client.stub_responses(:describe_log_streams, Aws::Errors::MissingCredentialsError.new('no creds'))
      client.stub_responses(:get_log_events, Aws::Errors::MissingCredentialsError.new('no creds'))
      client.stub_responses(:filter_log_events, Aws::Errors::MissingCredentialsError.new('no creds'))
      client
    end

    let(:failing_backend) do
      described_class.new(
        log_group: '/app/production',
        region: 'us-east-1',
        aws_client: failing_client
      )
    end

    it 'returns a credential error from streams' do
      result = failing_backend.streams

      expect(result[:error]).to eq('AWS credentials missing')
      expect(result[:message]).to include('credentials')
    end

    it 'returns a credential error from read' do
      result = failing_backend.read(stream_name: 'web/host-1', lines: 10)

      expect(result[:error]).to eq('AWS credentials missing')
    end

    it 'returns a credential error from search' do
      result = failing_backend.search(pattern: 'test')

      expect(result[:error]).to eq('AWS credentials missing')
    end
  end
end

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

  let(:now) { Time.now }
  let(:start_time) { now - 3600 }
  let(:end_time) { now }

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

    it 'returns an error hash on service failure' do
      client.stub_responses(:describe_log_streams, 'ResourceNotFoundException')

      result = backend.streams

      expect(result[:error]).to eq('CloudWatch service error')
    end
  end

  describe '#query' do
    it 'returns log events with parsed fields' do
      now_ms = (now.to_f * 1000).to_i
      client.stub_responses(:filter_log_events, {
        events: [
          { timestamp: now_ms - 2000, message: 'INFO -- Started GET /users', log_stream_name: 'web/host-1', event_id: '1' },
          { timestamp: now_ms - 1000, message: 'ERROR -- Connection refused', log_stream_name: 'web/host-1', event_id: '2' }
        ],
        next_token: nil
      })

      result = backend.query(start_time: start_time, end_time: end_time, limit: 10)

      expect(result[:lines].length).to eq(2)
      expect(result[:lines].first[:message]).to include('Started GET')
      expect(result[:lines].first[:timestamp]).to be_a(Time)
      expect(result[:lines].first[:severity]).to eq('INFO')
      expect(result[:lines].first[:stream]).to eq('web/host-1')
      expect(result[:lines].last[:severity]).to eq('ERROR')
    end

    it 'returns cursors for pagination' do
      now_ms = (now.to_f * 1000).to_i
      client.stub_responses(:filter_log_events, {
        events: [
          { timestamp: now_ms, message: 'INFO test', log_stream_name: 'web/host-1', event_id: '1' }
        ],
        next_token: nil
      })

      result = backend.query(start_time: start_time, end_time: end_time, limit: 10)

      expect(result[:cursors][:older]).to start_with('t:')
      expect(result[:cursors][:newer]).to start_with('t:')
    end

    it 'limits results to the requested count' do
      now_ms = (now.to_f * 1000).to_i
      events = 10.times.map do |i|
        { timestamp: now_ms + i, message: "INFO Line #{i}", log_stream_name: 'web/host-1', event_id: i.to_s }
      end
      client.stub_responses(:filter_log_events, {
        events: events,
        next_token: nil
      })

      result = backend.query(start_time: start_time, end_time: end_time, limit: 5)

      expect(result[:lines].length).to eq(5)
    end

    it 'passes search as filter_pattern' do
      client.stub_responses(:filter_log_events, {
        events: [],
        next_token: nil
      })

      expect(client).to receive(:filter_log_events)
        .with(hash_including(filter_pattern: '"connection refused"'))
        .and_call_original

      backend.query(start_time: start_time, end_time: end_time, search: 'connection refused', limit: 10)
    end

    it 'returns an error hash on service failure' do
      client.stub_responses(:filter_log_events, 'ResourceNotFoundException')

      result = backend.query(start_time: start_time, end_time: end_time, limit: 10)

      expect(result[:error]).to eq('CloudWatch service error')
    end
  end

  describe 'redaction' do
    it 'redacts default patterns automatically' do
      now_ms = (now.to_f * 1000).to_i
      client.stub_responses(:filter_log_events, {
        events: [
          { timestamp: now_ms, message: 'Login password=hunter2 completed', log_stream_name: 'web/host-1', event_id: '1' }
        ],
        next_token: nil
      })

      result = backend.query(start_time: start_time, end_time: end_time, limit: 10)

      expect(result[:lines].first[:message]).to eq('Login [REDACTED] completed')
      expect(result[:lines].first[:message]).not_to include('hunter2')
    end

    it 'redacts user-configured patterns on top of defaults' do
      RailsLogViewer.configure do |c|
        c.redact_patterns = [/session_id=\S+/]
      end

      now_ms = (now.to_f * 1000).to_i
      client.stub_responses(:filter_log_events, {
        events: [
          { timestamp: now_ms, message: 'Request session_id=xyz789 completed', log_stream_name: 'web/host-1', event_id: '1' }
        ],
        next_token: nil
      })

      result = backend.query(start_time: start_time, end_time: end_time, limit: 10)

      expect(result[:lines].first[:message]).to eq('Request [REDACTED] completed')
    end
  end

  describe 'credential errors' do
    let(:failing_client) do
      c = Aws::CloudWatchLogs::Client.new(stub_responses: true)
      c.stub_responses(:describe_log_streams, Aws::Errors::MissingCredentialsError.new('no creds'))
      c.stub_responses(:filter_log_events, Aws::Errors::MissingCredentialsError.new('no creds'))
      c
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

    it 'returns a credential error from query' do
      result = failing_backend.query(start_time: start_time, end_time: end_time, limit: 10)

      expect(result[:error]).to eq('AWS credentials missing')
    end
  end
end

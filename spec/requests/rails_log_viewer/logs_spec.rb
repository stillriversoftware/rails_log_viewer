require 'rails_helper'

RSpec.describe 'RailsLogViewer::Logs', type: :request do
  let(:fixture_path) { File.expand_path('../../fixtures/test.log', __dir__) }
  let(:local_backend) { RailsLogViewer::Backends::Local.new(log_path: fixture_path) }

  def authenticate!
    RailsLogViewer.configure do |c|
      c.authenticate_with = ->(_controller) { true }
    end
  end

  def configure_local!
    authenticate!
    RailsLogViewer.configure do |c|
      c.source = :local
      c.lines_per_page = 5
    end
    allow_any_instance_of(RailsLogViewer::LogsController).to receive(:build_backend)
      .and_return(local_backend)
  end

  describe 'authentication' do
    it 'returns 403 when authenticate_with returns false' do
      RailsLogViewer.configure do |c|
        c.authenticate_with = ->(_controller) { false }
      end

      get '/log_viewer/logs'

      expect(response).to have_http_status(:forbidden)
      body = JSON.parse(response.body)
      expect(body['error']).to eq('Forbidden')
    end

    it 'raises ConfigurationError when authenticate_with is nil' do
      expect {
        get '/log_viewer/logs'
      }.to raise_error(RailsLogViewer::ConfigurationError, /authenticate_with/)
    end

    it 'allows access when authenticate_with returns truthy' do
      configure_local!

      get '/log_viewer/logs'

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET /log_viewer/logs (index)' do
    it 'returns available sources as JSON' do
      configure_local!

      get '/log_viewer/logs', headers: { 'Accept' => 'application/json' }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['sources']).to eq(['local'])
    end

    it 'returns HTML when requested without JSON accept header' do
      configure_local!

      get '/log_viewer/logs'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="rlv-app"')
      expect(response.body).to include('id="rlv-output"')
    end

    it 'includes streams for cloudwatch source' do
      authenticate!
      RailsLogViewer.configure do |c|
        c.source = :cloudwatch
        c.aws_log_group = '/app/production'
        c.aws_region = 'us-east-1'
      end

      stub_client = Aws::CloudWatchLogs::Client.new(stub_responses: true)
      stub_client.stub_responses(:describe_log_streams, {
        log_streams: [
          { log_stream_name: 'web/host-1', last_event_timestamp: 1000 }
        ]
      })
      allow(Aws::CloudWatchLogs::Client).to receive(:new).and_return(stub_client)

      get '/log_viewer/logs', headers: { 'Accept' => 'application/json' }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['sources']).to eq(['cloudwatch'])
      expect(body['streams']).to eq(['web/host-1'])
    end
  end

  describe 'GET /log_viewer/logs/:id (show)' do
    before { configure_local! }

    it 'returns paginated log lines as JSON' do
      get '/log_viewer/logs/local', params: { source: 'local', page: 0 }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['lines'].length).to eq(5)
      expect(body['pagination']['page']).to eq(0)
      expect(body['pagination']['has_more']).to be true
      expect(body['source']).to eq('local')
    end

    it 'supports page-based pagination' do
      get '/log_viewer/logs/local', params: { source: 'local', page: 1 }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['lines'].length).to eq(5)
      expect(body['pagination']['page']).to eq(1)
    end

    it 'returns search results when query is provided' do
      get '/log_viewer/logs/local', params: { source: 'local', query: 'ERROR' }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      body['lines'].each do |line|
        expect(line).to include('ERROR')
      end
    end

    it 'returns 500 with error details when backend returns an error' do
      error_backend = instance_double(RailsLogViewer::Backends::Local)
      allow(error_backend).to receive(:read)
        .and_return({ error: 'Log file not found', path: '/missing.log' })
      allow_any_instance_of(RailsLogViewer::LogsController).to receive(:build_backend)
        .and_return(error_backend)

      get '/log_viewer/logs/local', params: { source: 'local' }

      expect(response).to have_http_status(:internal_server_error)
      body = JSON.parse(response.body)
      expect(body['error']).to eq('Log file not found')
    end
  end
end

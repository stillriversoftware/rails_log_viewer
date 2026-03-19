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

      get '/log_viewer/'

      expect(response).to have_http_status(:forbidden)
      body = JSON.parse(response.body)
      expect(body['error']).to eq('Forbidden')
    end

    it 'raises ConfigurationError when authenticate_with is nil' do
      expect {
        get '/log_viewer/'
      }.to raise_error(RailsLogViewer::ConfigurationError, /authenticate_with/)
    end

    it 'allows access when authenticate_with returns truthy' do
      configure_local!

      get '/log_viewer/'

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET /log_viewer/ (index)' do
    it 'returns the HTML log viewer interface' do
      configure_local!

      get '/log_viewer/'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="rlv-app"')
      expect(response.body).to include('id="rlv-output"')
      expect(response.body).to include('id="rlv-time-range"')
      expect(response.body).to include('rlv-sev-btn')
    end
  end

  describe 'GET /log_viewer/query (query)' do
    before { configure_local! }

    it 'returns log lines as JSON' do
      get '/log_viewer/query', params: { limit: 5 }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['lines'].length).to eq(5)
      expect(body['cursors']).to have_key('older')
      expect(body['cursors']).to have_key('newer')
    end

    it 'returns structured line objects with message, timestamp, severity' do
      get '/log_viewer/query', params: { limit: 1 }

      body = JSON.parse(response.body)
      line = body['lines'].first
      expect(line).to have_key('message')
      expect(line).to have_key('timestamp')
      expect(line).to have_key('severity')
    end

    it 'supports time range filtering' do
      get '/log_viewer/query', params: {
        start_time: '2026-03-19T10:00:03',
        end_time: '2026-03-19T10:00:04',
        limit: 100
      }

      body = JSON.parse(response.body)
      expect(body['lines']).not_to be_empty
      body['lines'].each do |line|
        ts = Time.parse(line['timestamp'])
        expect(ts).to be >= Time.new(2026, 3, 19, 10, 0, 3)
        expect(ts).to be <= Time.new(2026, 3, 19, 10, 0, 4)
      end
    end

    it 'supports severity filtering' do
      get '/log_viewer/query', params: { severity: 'ERROR', limit: 100 }

      body = JSON.parse(response.body)
      expect(body['lines']).not_to be_empty
      body['lines'].each do |line|
        expect(line['severity']).to eq('ERROR')
      end
    end

    it 'supports search' do
      get '/log_viewer/query', params: { q: 'ConnectionBad', limit: 100 }

      body = JSON.parse(response.body)
      expect(body['lines'].length).to eq(1)
      expect(body['lines'].first['message']).to include('ConnectionBad')
    end

    it 'supports cursor-based pagination' do
      get '/log_viewer/query', params: { limit: 5 }
      first_body = JSON.parse(response.body)
      cursor = first_body['cursors']['older']

      get '/log_viewer/query', params: { limit: 5, cursor: cursor, direction: 'older' }
      second_body = JSON.parse(response.body)

      first_messages = first_body['lines'].map { |l| l['message'] }
      second_messages = second_body['lines'].map { |l| l['message'] }
      expect(first_messages & second_messages).to be_empty
    end

    it 'returns 500 with error details when backend returns an error' do
      error_backend = instance_double(RailsLogViewer::Backends::Local)
      allow(error_backend).to receive(:query)
        .and_return({ error: 'Log file not found', path: '/missing.log' })
      allow_any_instance_of(RailsLogViewer::LogsController).to receive(:build_backend)
        .and_return(error_backend)

      get '/log_viewer/query', params: { limit: 10 }

      expect(response).to have_http_status(:internal_server_error)
      body = JSON.parse(response.body)
      expect(body['error']).to eq('Log file not found')
    end
  end
end

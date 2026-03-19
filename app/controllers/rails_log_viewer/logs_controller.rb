module RailsLogViewer
  class LogsController < ApplicationController
    include ActionController::Live if defined?(ActionController::Live)

    def index
      config = RailsLogViewer.configuration
      @source = config.source
      @streams = []

      if config.source == :cloudwatch
        backend = build_backend
        stream_names = backend.streams
        @streams = stream_names unless stream_names.is_a?(Hash) && stream_names[:error]
      end
    end

    def query
      backend = build_backend
      params_hash = query_params
      result = backend.query(**params_hash)

      if result[:error]
        render json: result, status: :internal_server_error
      else
        render json: result
      end
    end

    def stream
      response.headers['Content-Type'] = 'text/event-stream'
      response.headers['Cache-Control'] = 'no-cache'
      response.headers['X-Accel-Buffering'] = 'no'

      backend = build_backend
      last_cursor = nil

      loop do
        params_hash = {
          start_time: 30.seconds.ago,
          end_time: Time.now,
          limit: 50,
          direction: :newer
        }
        params_hash[:cursor] = last_cursor if last_cursor
        params_hash[:stream] = params[:stream] if params[:stream]

        result = backend.query(**params_hash)
        break if result[:error]

        if result[:lines].any?
          response.stream.write("data: #{result[:lines].to_json}\n\n")
          last_cursor = result[:cursors][:newer]
        end

        sleep 2
      end
    rescue IOError, ActionController::Live::ClientDisconnected
    ensure
      response.stream.close if response.stream.respond_to?(:close)
    end

    private

    def build_backend
      config = RailsLogViewer.configuration
      case config.source
      when :cloudwatch
        Backends::Cloudwatch.new(
          log_group: config.aws_log_group,
          log_stream_prefix: config.aws_log_stream_prefix,
          region: config.aws_region
        )
      else
        Backends::Local.new
      end
    end

    def query_params
      h = {}
      h[:start_time] = Time.parse(params[:start_time]) if params[:start_time].present?
      h[:end_time] = Time.parse(params[:end_time]) if params[:end_time].present?
      h[:search] = params[:q] if params[:q].present?
      h[:severity] = params[:severity].split(',') if params[:severity].present?
      h[:cursor] = params[:cursor] if params[:cursor].present?
      h[:direction] = params[:direction]&.to_sym || :older
      h[:limit] = (params[:limit] || RailsLogViewer.configuration.lines_per_page).to_i
      h
    end
  end
end

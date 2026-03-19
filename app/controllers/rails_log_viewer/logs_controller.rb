module RailsLogViewer
  class LogsController < ApplicationController
    include ActionController::Live if defined?(ActionController::Live)

    def index
      config = RailsLogViewer.configuration
      @source = config.source
      @sources = [config.source]
      @streams = []

      if config.source == :cloudwatch
        backend = build_cloudwatch_backend
        stream_names = backend.streams
        @streams = stream_names unless stream_names.is_a?(Hash) && stream_names[:error]
      end

      respond_to do |format|
        format.html
        format.json { render json: { sources: @sources, streams: @streams } }
      end
    end

    def show
      config = RailsLogViewer.configuration
      source = (params[:source] || config.source).to_sym
      page = (params[:page] || 0).to_i
      query = params[:query]
      lines_per_page = config.lines_per_page

      backend = build_backend(source)
      result = fetch_logs(backend, source, page, query, lines_per_page)

      return render json: result, status: :internal_server_error if result[:error]

      has_more = if result[:truncated] != nil
        result[:truncated]
      else
        result[:has_more] || false
      end

      render json: {
        lines: result[:lines],
        pagination: { page: page, has_more: has_more },
        source: source
      }
    end

    def stream
      response.headers['Content-Type'] = 'text/event-stream'
      response.headers['Cache-Control'] = 'no-cache'
      response.headers['X-Accel-Buffering'] = 'no'

      config = RailsLogViewer.configuration
      source = (params[:source] || config.source).to_sym
      backend = build_backend(source)
      last_line_count = 0

      loop do
        result = fetch_latest(backend, source, config.lines_per_page)
        break if result[:error]

        lines = result[:lines]
        current_count = lines.length

        if current_count > last_line_count
          new_lines = lines.last(current_count - last_line_count)
          response.stream.write("data: #{new_lines.to_json}\n\n")
          last_line_count = current_count
        end

        sleep 2
      end
    rescue IOError, ActionController::Live::ClientDisconnected
    ensure
      response.stream.close if response.stream.respond_to?(:close)
    end

    private

    def build_backend(source)
      case source
      when :cloudwatch
        build_cloudwatch_backend
      else
        Backends::Local.new
      end
    end

    def build_cloudwatch_backend
      config = RailsLogViewer.configuration
      Backends::Cloudwatch.new(
        log_group: config.aws_log_group,
        log_stream_prefix: config.aws_log_stream_prefix,
        region: config.aws_region
      )
    end

    def fetch_logs(backend, source, page, query, lines_per_page)
      if query && !query.empty?
        fetch_search(backend, source, query, lines_per_page)
      else
        fetch_read(backend, source, page, lines_per_page)
      end
    end

    def fetch_read(backend, source, page, lines_per_page)
      case source
      when :cloudwatch
        stream_name = params[:stream]
        backend.read(stream_name: stream_name, lines: lines_per_page)
      else
        offset = page * lines_per_page
        backend.read(lines: lines_per_page, offset: offset)
      end
    end

    def fetch_search(backend, source, query, lines_per_page)
      case source
      when :cloudwatch
        backend.search(pattern: query)
      else
        backend.search(pattern: query, lines: lines_per_page)
      end
    end

    def fetch_latest(backend, source, lines_per_page)
      case source
      when :cloudwatch
        stream_name = params[:stream]
        backend.read(stream_name: stream_name, lines: lines_per_page)
      else
        backend.read(lines: lines_per_page)
      end
    end
  end
end

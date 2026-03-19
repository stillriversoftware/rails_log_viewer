require 'aws-sdk-cloudwatchlogs'

module RailsLogViewer
  module Backends
    class Cloudwatch
      MAX_RETRIES = 3
      BASE_BACKOFF = 0.5

      def initialize(options = {})
        @log_group = options.fetch(:log_group)
        @log_stream_prefix = options.fetch(:log_stream_prefix, nil)
        @region = options.fetch(:region) { ENV['AWS_REGION'] }
        @client = options.fetch(:aws_client) { build_client }
      end

      def streams(limit: 10)
        params = {
          log_group_name: @log_group,
          order_by: 'LastEventTime',
          descending: true,
          limit: limit
        }
        params[:log_stream_name_prefix] = @log_stream_prefix if @log_stream_prefix

        resp = with_retries { @client.describe_log_streams(params) }
        resp.log_streams.map(&:log_stream_name)
      rescue Aws::CloudWatchLogs::Errors::ServiceError => e
        service_error(e)
      rescue Aws::Errors::MissingCredentialsError
        credentials_error
      end

      def query(start_time: nil, end_time: nil, search: nil, severity: nil, cursor: nil, direction: :older, limit: 100, **)
        effective_start = start_time || (Time.now - 3600)
        effective_end = end_time || Time.now
        effective_start, effective_end = resolve_time_range(effective_start, effective_end, cursor, direction)

        params = {
          log_group_name: @log_group,
          start_time: to_epoch_ms(effective_start),
          end_time: to_epoch_ms(effective_end),
          limit: limit
        }
        params[:filter_pattern] = build_filter_pattern(search, severity) if search || severity
        params[:log_stream_name_prefix] = @log_stream_prefix if @log_stream_prefix

        collected = []
        token = nil

        loop do
          params[:next_token] = token if token
          resp = with_retries { @client.filter_log_events(params) }

          resp.events.each do |event|
            collected << {
              message: event.message,
              timestamp: Time.at(event.timestamp / 1000.0).utc,
              severity: LogParser.extract_severity(event.message),
              stream: event.log_stream_name
            }
          end

          break if collected.length >= limit
          break unless resp.next_token
          break if resp.next_token == token
          token = resp.next_token
        end

        collected = collected.first(limit)
        collected = redact(collected)

        cursor_older = nil
        cursor_newer = nil

        if collected.any?
          oldest_ts = collected.first[:timestamp]
          newest_ts = collected.last[:timestamp]
          cursor_older = "t:#{to_epoch_ms(oldest_ts)}"
          cursor_newer = "t:#{to_epoch_ms(newest_ts)}"
        end

        {
          lines: collected,
          cursors: { older: cursor_older, newer: cursor_newer }
        }
      rescue Aws::CloudWatchLogs::Errors::ServiceError => e
        service_error(e)
      rescue Aws::Errors::MissingCredentialsError
        credentials_error
      end

      private

      def resolve_time_range(start_time, end_time, cursor, direction)
        if cursor && cursor.start_with?('t:')
          cursor_time = Time.at(cursor[2..].to_i / 1000.0).utc
          case direction
          when :older
            [start_time, cursor_time]
          when :newer
            [cursor_time, end_time]
          else
            [start_time, end_time]
          end
        else
          [start_time, end_time]
        end
      end

      def build_filter_pattern(search, severity)
        parts = []
        parts << "\"#{search}\"" if search && !search.empty?
        if severity && !severity.empty?
          severity_terms = Array(severity).map { |s| "\"#{s}\"" }
          parts << severity_terms.join(' || ') if severity_terms.length == 1
          parts.concat(severity_terms) if severity_terms.length > 1
        end
        parts.any? ? parts.join(' ') : nil
      end

      def with_retries
        retries = 0
        begin
          yield
        rescue Aws::CloudWatchLogs::Errors::ThrottlingException,
               Aws::CloudWatchLogs::Errors::LimitExceededException => e
          retries += 1
          raise if retries > MAX_RETRIES
          sleep(BASE_BACKOFF * (2**retries))
          retry
        end
      end

      def build_client
        Aws::CloudWatchLogs::Client.new(region: @region)
      end

      def to_epoch_ms(time)
        (time.to_f * 1000).to_i
      end

      def redact(entries)
        Redactor.redact_lines(entries)
      end

      def service_error(exception)
        { error: 'CloudWatch service error', message: exception.message }
      end

      def credentials_error
        { error: 'AWS credentials missing', message: 'Configure AWS credentials via environment variables, IAM role, or shared credentials file' }
      end
    end
  end
end

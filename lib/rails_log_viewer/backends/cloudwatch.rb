require 'aws-sdk-cloudwatchlogs'

module RailsLogViewer
  module Backends
    class Cloudwatch
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

        resp = @client.describe_log_streams(params)
        resp.log_streams.map(&:log_stream_name)
      rescue Aws::CloudWatchLogs::Errors::ServiceError => e
        service_error(e)
      rescue Aws::Errors::MissingCredentialsError
        credentials_error
      end

      def read(stream_name:, lines:, start_time: nil, end_time: nil)
        params = {
          log_group_name: @log_group,
          log_stream_name: stream_name,
          limit: lines,
          start_from_head: false
        }
        params[:start_time] = to_epoch_ms(start_time) if start_time
        params[:end_time] = to_epoch_ms(end_time) if end_time

        collected = []
        token = nil

        loop do
          params[:next_token] = token if token
          resp = @client.get_log_events(params)

          resp.events.each do |event|
            collected << {
              timestamp: Time.at(event.timestamp / 1000.0),
              message: event.message
            }
          end

          new_token = resp.next_forward_token
          same_token = new_token == token
          token = new_token
          break if collected.length >= lines
          break if same_token
        end

        collected = collected.last(lines)

        {
          lines: redact(collected),
          stream: stream_name,
          has_more: !token.nil? && collected.length >= lines
        }
      rescue Aws::CloudWatchLogs::Errors::ServiceError => e
        service_error(e)
      rescue Aws::Errors::MissingCredentialsError
        credentials_error
      end

      def search(pattern:, hours_back: 1)
        now = Time.now
        start_ms = to_epoch_ms(now - (hours_back * 3600))
        end_ms = to_epoch_ms(now)

        params = {
          log_group_name: @log_group,
          start_time: start_ms,
          end_time: end_ms,
          filter_pattern: pattern.to_s
        }
        params[:log_stream_name_prefix] = @log_stream_prefix if @log_stream_prefix

        collected = []
        token = nil

        loop do
          params[:next_token] = token if token
          resp = @client.filter_log_events(params)

          resp.events.each do |event|
            collected << {
              timestamp: Time.at(event.timestamp / 1000.0),
              message: event.message,
              stream: event.log_stream_name
            }
          end

          break unless resp.next_token
          break if resp.next_token == token
          token = resp.next_token
        end

        {
          lines: redact(collected),
          stream: @log_group,
          has_more: false
        }
      rescue Aws::CloudWatchLogs::Errors::ServiceError => e
        service_error(e)
      rescue Aws::Errors::MissingCredentialsError
        credentials_error
      end

      private

      def build_client
        Aws::CloudWatchLogs::Client.new(region: @region)
      end

      def to_epoch_ms(time)
        (time.to_f * 1000).to_i
      end

      def redact(entries)
        patterns = RailsLogViewer.configuration.redact_patterns
        return entries if patterns.empty?

        entries.map do |entry|
          redacted_message = patterns.reduce(entry[:message]) { |msg, pat| msg.gsub(pat, '[REDACTED]') }
          entry.merge(message: redacted_message)
        end
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

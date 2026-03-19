require 'aws-sdk-s3'
require 'zlib'
require 'stringio'

module RailsLogViewer
  module Backends
    class S3
      MAX_RETRIES = 3
      BASE_BACKOFF = 0.5

      def initialize(options = {})
        @bucket = options.fetch(:bucket)
        @prefix = options.fetch(:prefix, '')
        @region = options.fetch(:region) { ENV['AWS_REGION'] }
        @client = options.fetch(:aws_client) { build_client }
      end

      def files(limit: 20)
        params = {
          bucket: @bucket,
          prefix: @prefix,
          max_keys: limit
        }

        collected = []
        resp = with_retries { @client.list_objects_v2(**params) }

        resp.contents
          .select { |obj| log_file?(obj.key) }
          .sort_by { |obj| obj.last_modified }
          .reverse
          .first(limit)
          .map do |obj|
            {
              key: obj.key,
              size: obj.size,
              last_modified: obj.last_modified,
              name: File.basename(obj.key)
            }
          end
      rescue Aws::S3::Errors::ServiceError => e
        service_error(e)
      rescue Aws::Errors::MissingCredentialsError
        credentials_error
      end

      def query(start_time: nil, end_time: nil, search: nil, severity: nil, cursor: nil, direction: :older, limit: 100, file_key: nil)
        if file_key
          query_single_file(file_key, start_time: start_time, end_time: end_time, search: search, severity: severity, cursor: cursor, direction: direction, limit: limit)
        else
          query_across_files(start_time: start_time, end_time: end_time, search: search, severity: severity, cursor: cursor, direction: direction, limit: limit)
        end
      rescue Aws::S3::Errors::ServiceError => e
        service_error(e)
      rescue Aws::Errors::MissingCredentialsError
        credentials_error
      end

      private

      def query_single_file(file_key, start_time: nil, end_time: nil, search: nil, severity: nil, cursor: nil, direction: :older, limit: 100)
        content = download_file(file_key)
        return { error: 'File not found', key: file_key } unless content

        lines_array = content.split("\n").reject(&:empty?)
        search_re = build_search_regex(search)
        severity_set = normalize_severity(severity)

        parsed_lines = parse_lines(lines_array)
        filtered = filter_lines(parsed_lines, start_time: start_time, end_time: end_time, search: search_re, severity: severity_set)

        offset = 0
        if cursor
          offset = parse_cursor_offset(cursor)
        end

        result_lines = case direction
        when :newer
          filtered.select { |l| l[:_index] > offset }.first(limit)
        else
          candidates = offset > 0 ? filtered.select { |l| l[:_index] < offset } : filtered
          candidates.last(limit)
        end

        result_lines = Redactor.redact_lines(result_lines)

        cursor_older = nil
        cursor_newer = nil

        if result_lines.any?
          cursor_older = "s3:#{file_key}:#{result_lines.first[:_index]}" if result_lines.first[:_index] > 0
          cursor_newer = "s3:#{file_key}:#{result_lines.last[:_index]}"
        end

        result_lines.each { |l| l.delete(:_index) }

        {
          lines: result_lines,
          cursors: { older: cursor_older, newer: cursor_newer },
          file: file_key
        }
      end

      def query_across_files(start_time: nil, end_time: nil, search: nil, severity: nil, cursor: nil, direction: :older, limit: 100)
        file_list = files(limit: 50)
        return file_list if file_list.is_a?(Hash) && file_list[:error]

        file_key = nil
        cursor_offset = 0

        if cursor
          file_key, cursor_offset = parse_s3_cursor(cursor)
        end

        if file_key
          return query_single_file(file_key, start_time: start_time, end_time: end_time, search: search, severity: severity, cursor: cursor, direction: direction, limit: limit)
        end

        target_file = find_file_for_time_range(file_list, start_time, end_time)
        return empty_result unless target_file

        query_single_file(target_file[:key], start_time: start_time, end_time: end_time, search: search, severity: severity, limit: limit)
      end

      def find_file_for_time_range(file_list, start_time, end_time)
        return file_list.first if start_time.nil? && end_time.nil?

        target_time = end_time || start_time || Time.now
        file_list.min_by do |f|
          (f[:last_modified] - target_time).abs
        end
      end

      def download_file(key)
        resp = with_retries { @client.get_object(bucket: @bucket, key: key) }
        body = resp.body.read

        if key.end_with?('.gz')
          decompress_gzip(body)
        else
          body.force_encoding('UTF-8')
        end
      rescue Aws::S3::Errors::NoSuchKey
        nil
      end

      def decompress_gzip(data)
        gz = Zlib::GzipReader.new(StringIO.new(data))
        gz.read.force_encoding('UTF-8')
      ensure
        gz&.close
      end

      def parse_lines(lines_array)
        fallback_time = nil
        lines_array.each_with_index.map do |raw_line, index|
          parsed = LogParser.parse(raw_line, fallback_time: fallback_time)
          fallback_time = parsed[:timestamp] if parsed[:timestamp]
          parsed[:_index] = index
          parsed
        end
      end

      def filter_lines(parsed_lines, start_time: nil, end_time: nil, search: nil, severity: nil)
        parsed_lines.select do |line|
          next false if line[:timestamp] && start_time && line[:timestamp] < start_time
          next false if line[:timestamp] && end_time && line[:timestamp] > end_time
          next false if severity && line[:severity] && !severity.include?(line[:severity])
          next false if search && !line[:message].match?(search)
          true
        end
      end

      def build_search_regex(search)
        return nil if search.nil? || search.empty?
        Regexp.new(Regexp.escape(search), Regexp::IGNORECASE)
      end

      def normalize_severity(severity)
        return nil if severity.nil? || severity.empty?
        Array(severity).map(&:upcase)
      end

      def parse_cursor_offset(cursor)
        if cursor.include?(':')
          parts = cursor.split(':')
          parts.last.to_i
        else
          0
        end
      end

      def parse_s3_cursor(cursor)
        return [nil, 0] unless cursor&.start_with?('s3:')
        parts = cursor.sub('s3:', '').rpartition(':')
        [parts[0], parts[2].to_i]
      end

      def log_file?(key)
        key.match?(/\.log(\.gz)?$|\.txt(\.gz)?$/i) && !key.end_with?('/')
      end

      def empty_result
        { lines: [], cursors: { older: nil, newer: nil } }
      end

      def with_retries
        retries = 0
        begin
          yield
        rescue Aws::S3::Errors::Throttling, Aws::S3::Errors::SlowDown => e
          retries += 1
          raise if retries > MAX_RETRIES
          sleep(BASE_BACKOFF * (2**retries))
          retry
        end
      end

      def build_client
        Aws::S3::Client.new(region: @region)
      end

      def service_error(exception)
        { error: 'S3 service error', message: exception.message }
      end

      def credentials_error
        { error: 'AWS credentials missing', message: 'Configure AWS credentials via environment variables, IAM role, or shared credentials file' }
      end
    end
  end
end

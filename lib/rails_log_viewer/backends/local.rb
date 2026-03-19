module RailsLogViewer
  module Backends
    class Local
      def initialize(options = {})
        @log_path = options.fetch(:log_path) {
          defined?(Rails) ? Rails.root.join('log', 'production.log').to_s : 'log/production.log'
        }
      end

      def query(start_time: nil, end_time: nil, search: nil, severity: nil, cursor: nil, direction: :older, limit: 100)
        return file_error unless readable?

        search_re = build_search_regex(search)
        severity_set = normalize_severity(severity)
        byte_cursor = parse_cursor(cursor)

        lines = case direction
        when :newer
          read_forward(byte_cursor || 0, limit, start_time: start_time, end_time: end_time, search: search_re, severity: severity_set)
        else
          read_backward(byte_cursor, limit, start_time: start_time, end_time: end_time, search: search_re, severity: severity_set)
        end

        lines = redact(lines)

        cursor_older = nil
        cursor_newer = nil

        if lines.any?
          cursor_older = "b:#{lines.first[:_byte_start]}" if lines.first[:_byte_start] && lines.first[:_byte_start] > 0
          cursor_newer = "b:#{lines.last[:_byte_end]}" if lines.last[:_byte_end]
        end

        lines.each { |l| l.delete(:_byte_start); l.delete(:_byte_end) }

        {
          lines: lines,
          cursors: { older: cursor_older, newer: cursor_newer }
        }
      rescue Errno::EACCES
        permission_error
      rescue Errno::ENOENT
        file_not_found_error
      end

      private

      def readable?
        return file_not_found_error unless File.exist?(@log_path)
        return permission_error unless File.readable?(@log_path)
        true
      end

      def file_error
        return file_not_found_error unless File.exist?(@log_path)
        permission_error
      end

      def read_backward(from_byte, limit, start_time: nil, end_time: nil, search: nil, severity: nil)
        collected = []
        fallback_time = nil

        File.open(@log_path, 'rb') do |f|
          pos = from_byte || f.size
          buf = +''

          while pos > 0 && collected.length < limit
            chunk_size = [8192, pos].min
            pos -= chunk_size
            f.seek(pos, IO::SEEK_SET)
            chunk = f.read(chunk_size)
            buf.prepend(chunk)

            while (idx = buf.rindex("\n", [buf.length - 2, 0].max))
              raw_line = buf[(idx + 1)..].chomp
              line_end_byte = pos + buf.length
              line_start_byte = pos + idx + 1
              buf = buf[0..idx]

              next if raw_line.empty?

              parsed = LogParser.parse(raw_line, fallback_time: fallback_time)
              fallback_time = parsed[:timestamp] if parsed[:timestamp]

              next unless matches_filters?(parsed, start_time: start_time, end_time: end_time, search: search, severity: severity)

              if parsed[:timestamp] && start_time && parsed[:timestamp] < start_time
                return collected.reverse
              end

              parsed[:_byte_start] = line_start_byte
              parsed[:_byte_end] = line_end_byte
              collected << parsed
              break if collected.length >= limit
            end
          end

          if buf.strip.length > 0 && collected.length < limit
            parsed = LogParser.parse(buf.chomp, fallback_time: fallback_time)
            if matches_filters?(parsed, start_time: start_time, end_time: end_time, search: search, severity: severity)
              parsed[:_byte_start] = 0
              parsed[:_byte_end] = buf.length
              collected << parsed
            end
          end
        end

        collected.reverse
      end

      def read_forward(from_byte, limit, start_time: nil, end_time: nil, search: nil, severity: nil)
        collected = []
        fallback_time = nil

        File.open(@log_path, 'rb') do |f|
          f.seek(from_byte, IO::SEEK_SET)

          f.readline if from_byte > 0 rescue return collected

          while (raw_line = f.gets)
            line_end_byte = f.pos
            line_start_byte = line_end_byte - raw_line.bytesize
            raw_line = raw_line.chomp

            next if raw_line.empty?

            parsed = LogParser.parse(raw_line, fallback_time: fallback_time)
            fallback_time = parsed[:timestamp] if parsed[:timestamp]

            if parsed[:timestamp] && end_time && parsed[:timestamp] > end_time
              break
            end

            next unless matches_filters?(parsed, start_time: start_time, end_time: end_time, search: search, severity: severity)

            parsed[:_byte_start] = line_start_byte
            parsed[:_byte_end] = line_end_byte
            collected << parsed
            break if collected.length >= limit
          end
        end

        collected
      end

      def matches_filters?(parsed, start_time: nil, end_time: nil, search: nil, severity: nil)
        if parsed[:timestamp]
          return false if start_time && parsed[:timestamp] < start_time
          return false if end_time && parsed[:timestamp] > end_time
        end

        return false if severity && parsed[:severity] && !severity.include?(parsed[:severity])

        return false if search && !parsed[:message].match?(search)

        true
      end

      def build_search_regex(search)
        return nil if search.nil? || search.empty?
        Regexp.new(Regexp.escape(search), Regexp::IGNORECASE)
      end

      def normalize_severity(severity)
        return nil if severity.nil? || severity.empty?
        Array(severity).map(&:upcase)
      end

      def parse_cursor(cursor)
        return nil if cursor.nil? || cursor.empty?
        if cursor.start_with?('b:')
          cursor[2..].to_i
        end
      end

      def redact(lines)
        Redactor.redact_lines(lines)
      end

      def file_not_found_error
        { error: 'Log file not found', path: @log_path }
      end

      def permission_error
        { error: 'Permission denied', path: @log_path }
      end
    end
  end
end

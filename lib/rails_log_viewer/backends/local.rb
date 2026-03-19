module RailsLogViewer
  module Backends
    class Local
      def initialize(options = {})
        @log_path = options.fetch(:log_path) {
          defined?(Rails) ? Rails.root.join('log', 'production.log').to_s : 'log/production.log'
        }
      end

      def read(lines:, offset: 0)
        return file_not_found_error unless File.exist?(@log_path)
        return permission_error unless File.readable?(@log_path)

        total = estimated_line_count
        tail_count = offset + lines
        raw = tail_lines(tail_count)

        if offset > 0
          raw = raw.first(raw.length - offset)
        end
        raw = raw.last(lines)

        {
          lines: redact(raw),
          total_estimated: total,
          truncated: total > (offset + lines)
        }
      rescue Errno::EACCES
        permission_error
      rescue Errno::ENOENT
        file_not_found_error
      end

      def search(pattern:, lines: 500)
        return file_not_found_error unless File.exist?(@log_path)
        return permission_error unless File.readable?(@log_path)

        regexp = pattern.is_a?(Regexp) ? pattern : Regexp.new(Regexp.escape(pattern))
        matched = grep_from_tail(regexp, lines)
        total = estimated_line_count

        {
          lines: redact(matched),
          total_estimated: total,
          truncated: matched.length >= lines
        }
      rescue Errno::EACCES
        permission_error
      rescue Errno::ENOENT
        file_not_found_error
      end

      private

      def tail_lines(count)
        output = IO.popen(['tail', '-n', count.to_s, @log_path]) { |io| io.read }
        output.split("\n")
      end

      def grep_from_tail(regexp, limit)
        matches = []
        reverse_read_lines do |line|
          break if matches.length >= limit
          matches.unshift(line) if line.match?(regexp)
        end
        matches
      end

      def reverse_read_lines
        File.open(@log_path, 'rb') do |f|
          f.seek(0, IO::SEEK_END)
          pos = f.pos
          buf = +''

          while pos > 0
            chunk_size = [4096, pos].min
            pos -= chunk_size
            f.seek(pos, IO::SEEK_SET)
            chunk = f.read(chunk_size)
            buf.prepend(chunk)

            while (idx = buf.rindex("\n", buf.length - 2))
              line = buf[(idx + 1)..].chomp
              buf = buf[0..idx]
              yield line unless line.empty?
            end
          end

          yield buf.chomp unless buf.strip.empty?
        end
      end

      def estimated_line_count
        output = IO.popen(['wc', '-l', @log_path]) { |io| io.read }
        output.strip.split.first.to_i
      end

      def redact(lines)
        patterns = RailsLogViewer.configuration.redact_patterns
        return lines if patterns.empty?

        lines.map do |line|
          patterns.reduce(line) { |l, pat| l.gsub(pat, '[REDACTED]') }
        end
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

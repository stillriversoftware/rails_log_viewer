module RailsLogViewer
  module LogParser
    TIMESTAMP_PATTERNS = [
      /(\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:\s*[+-]\d{2}:?\d{2})?)/,
      /\[(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+)\s+#/,
    ].freeze

    SEVERITY_PATTERN = /\b(DEBUG|INFO|WARN(?:ING)?|ERROR|FATAL)\b/i

    RUBY_LOGGER_PREFIX = /\A([DIWEF]),\s*\[/

    SEVERITY_MAP = {
      'D' => 'DEBUG', 'I' => 'INFO', 'W' => 'WARN', 'E' => 'ERROR', 'F' => 'FATAL',
      'WARNING' => 'WARN'
    }.freeze

    module_function

    def parse(line, fallback_time: nil)
      {
        message: line,
        timestamp: extract_timestamp(line) || fallback_time,
        severity: extract_severity(line)
      }
    end

    def extract_timestamp(line)
      TIMESTAMP_PATTERNS.each do |pattern|
        if (match = line.match(pattern))
          return safe_parse_time(match[1])
        end
      end
      nil
    end

    def extract_severity(line)
      if (match = line.match(RUBY_LOGGER_PREFIX))
        return SEVERITY_MAP[match[1]] || 'INFO'
      end

      if (match = line.match(SEVERITY_PATTERN))
        severity = match[1].upcase
        return SEVERITY_MAP[severity] || severity
      end

      nil
    end

    def safe_parse_time(str)
      Time.parse(str)
    rescue ArgumentError, TypeError
      nil
    end
  end
end

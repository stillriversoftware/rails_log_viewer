module RailsLogViewer
  module Redactor
    DEFAULT_PATTERNS = [
      /(?:password|passwd|pass|pwd)=\S+/i,
      /(?:token|access_token|auth_token|api_token|refresh_token)=\S+/i,
      /(?:api_key|apikey|api-key|secret_key|secret)=\S+/i,
      /(?:secret_key_base)[:=]\s*\S+/i,
      /Authorization:\s*(?:Bearer|Basic|Token)\s+\S+/i,
      /Bearer\s+[A-Za-z0-9\-._~+\/]+=*/,
      /\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{3,4}\b/,
      /\b\d{3}-\d{2}-\d{4}\b/,
      /(?:private_key|private-key)[:=]\s*\S+/i,
      /(?:aws_secret_access_key|aws_access_key_id)[:=]\s*\S+/i,
      /(?:database_url|db_password)[:=]\s*\S+/i,
    ].freeze

    module_function

    def patterns
      config = RailsLogViewer.configuration
      result = config.redact_defaults ? DEFAULT_PATTERNS.dup : []
      result.concat(config.redact_patterns)
      result
    end

    def redact_line(line, active_patterns = nil)
      active_patterns ||= patterns
      return line if active_patterns.empty?

      active_patterns.reduce(line) { |l, pat| l.gsub(pat, '[REDACTED]') }
    end

    def redact_lines(lines)
      active_patterns = patterns
      return lines if active_patterns.empty?

      lines.map do |entry|
        if entry.is_a?(Hash) && entry[:message]
          entry.merge(message: redact_line(entry[:message], active_patterns))
        elsif entry.is_a?(String)
          redact_line(entry, active_patterns)
        else
          entry
        end
      end
    end
  end
end

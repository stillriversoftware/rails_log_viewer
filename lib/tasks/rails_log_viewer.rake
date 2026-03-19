namespace :rails_log_viewer do
  desc 'Validate RailsLogViewer configuration and print a summary'
  task check_config: :environment do
    config = RailsLogViewer.configuration
    errors = []

    puts 'RailsLogViewer Configuration'
    puts '=' * 40

    puts "Source:           #{config.source}"
    puts "Lines per page:   #{config.lines_per_page}"
    puts "Redact defaults:  #{config.redact_defaults ? 'enabled (' + RailsLogViewer::Redactor::DEFAULT_PATTERNS.length.to_s + ' built-in patterns)' : 'disabled'}"
    puts "Redact custom:    #{config.redact_patterns.length} pattern(s)"
    puts "Redact total:     #{RailsLogViewer::Redactor.patterns.length} active pattern(s)"

    if config.authenticate_with.nil?
      errors << 'authenticate_with is not configured (required)'
    else
      puts 'Auth:             configured'
    end

    if config.source == :cloudwatch
      puts "AWS log group:    #{config.aws_log_group || '(not set)'}"
      puts "AWS stream prefix:#{config.aws_log_stream_prefix || '(not set)'}"
      puts "AWS region:       #{config.aws_region || '(not set)'}"

      errors << 'aws_log_group is required for CloudWatch source' if config.aws_log_group.nil?
      errors << 'aws_region is required for CloudWatch source' if config.aws_region.nil?
    end

    puts '=' * 40

    if errors.any?
      puts "\nErrors:"
      errors.each { |e| puts "  - #{e}" }
      puts "\nConfiguration is INVALID."
      exit 1
    else
      puts "\nConfiguration is valid."
    end
  end
end

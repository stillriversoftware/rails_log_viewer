module RailsLogViewer
  class Configuration
    attr_accessor :source,
                  :aws_log_group,
                  :aws_log_stream_prefix,
                  :aws_region,
                  :s3_bucket,
                  :s3_prefix,
                  :s3_region,
                  :lines_per_page,
                  :redact_patterns,
                  :redact_defaults,
                  :authenticate_with

    def initialize
      @source = :local
      @aws_log_group = nil
      @aws_log_stream_prefix = nil
      @aws_region = ENV['AWS_REGION']
      @s3_bucket = nil
      @s3_prefix = ''
      @s3_region = ENV['AWS_REGION']
      @lines_per_page = 500
      @redact_patterns = []
      @redact_defaults = true
      @authenticate_with = nil
    end
  end
end

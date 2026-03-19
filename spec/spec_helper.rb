require 'rails_log_viewer/version'
require 'rails_log_viewer/configuration'
require 'rails_log_viewer/backends/local'
require 'rails_log_viewer/backends/cloudwatch'

module RailsLogViewer
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end

RSpec.configure do |config|
  config.before(:each) do
    RailsLogViewer.reset_configuration!
  end
end

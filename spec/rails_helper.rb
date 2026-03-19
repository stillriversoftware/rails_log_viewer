ENV['RAILS_ENV'] = 'test'

require_relative 'dummy/config/environment'
require 'rspec/rails'

RSpec.configure do |config|
  config.before(:each) do
    RailsLogViewer.reset_configuration!
  end
end

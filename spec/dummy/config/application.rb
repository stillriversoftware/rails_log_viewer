require 'rails'
require 'action_controller/railtie'
require 'rails_log_viewer'

module Dummy
  class Application < Rails::Application
    config.eager_load = false
    config.secret_key_base = 'test-secret-key-base-for-rails-log-viewer-specs'
    config.hosts.clear
    config.root = File.expand_path('..', __dir__)
    config.action_dispatch.show_exceptions = :rescuable
  end
end

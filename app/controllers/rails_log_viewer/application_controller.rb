module RailsLogViewer
  class ApplicationController < ActionController::Base
    before_action :authenticate_log_viewer!

    private

    def authenticate_log_viewer!
      auth_proc = RailsLogViewer.configuration.authenticate_with

      if auth_proc.nil?
        raise RailsLogViewer::ConfigurationError,
          'RailsLogViewer requires an authenticate_with proc. ' \
          'Configure it with: RailsLogViewer.configure { |c| c.authenticate_with = ->(controller) { controller.current_user&.admin? } }'
      end

      unless auth_proc.call(self)
        render json: { error: 'Forbidden' }, status: :forbidden
      end
    end
  end
end

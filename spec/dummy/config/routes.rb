Rails.application.routes.draw do
  mount RailsLogViewer::Engine, at: '/log_viewer'
end

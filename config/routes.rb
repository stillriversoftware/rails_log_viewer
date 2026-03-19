RailsLogViewer::Engine.routes.draw do
  root to: 'logs#index'
  get 'query', to: 'logs#query', as: :query
  get 'stream', to: 'logs#stream', as: :stream
end

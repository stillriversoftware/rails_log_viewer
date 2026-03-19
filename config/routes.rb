RailsLogViewer::Engine.routes.draw do
  get 'logs/stream', to: 'logs#stream'
  resources :logs, only: [:index, :show]
end

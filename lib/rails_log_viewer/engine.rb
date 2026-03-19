module RailsLogViewer
  class Engine < ::Rails::Engine
    isolate_namespace RailsLogViewer

    rake_tasks do
      load RailsLogViewer::Engine.root.join('lib', 'tasks', 'rails_log_viewer.rake')
    end
  end
end

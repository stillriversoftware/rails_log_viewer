require_relative 'lib/rails_log_viewer/version'

Gem::Specification.new do |spec|
  spec.name          = 'rails_log_viewer'
  spec.version       = RailsLogViewer::VERSION
  spec.authors       = ['Robb']
  spec.summary       = 'A mountable Rails engine for viewing application logs'
  spec.description   = 'View local and CloudWatch logs from a mounted Rails engine dashboard with a dark-themed UI, live tail, search, and redaction.'
  spec.homepage      = 'https://github.com/robb/rails_log_viewer'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.2'

  spec.metadata = {
    'homepage_uri' => spec.homepage,
    'source_code_uri' => 'https://github.com/robb/rails_log_viewer',
    'changelog_uri' => 'https://github.com/robb/rails_log_viewer/blob/main/CHANGELOG.md',
    'rubygems_mfa_required' => 'true'
  }

  spec.files = Dir.chdir(__dir__) do
    Dir['{app,config,lib}/**/*', 'LICENSE', 'README.md', 'CHANGELOG.md']
  end

  spec.require_paths = ['lib']

  spec.add_dependency 'aws-sdk-cloudwatchlogs', '~> 1.0'
  spec.add_dependency 'aws-sdk-s3', '~> 1.0'
  spec.add_dependency 'railties', '>= 6.0'

  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'rspec-rails', '~> 7.0'
end

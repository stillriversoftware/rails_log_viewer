# RailsLogViewer

A mountable Rails engine for viewing application logs. Supports local log files and AWS CloudWatch Logs with a dark-themed, real-time UI.

## Installation

Add to your Gemfile:

```ruby
gem 'rails_log_viewer'
```

Run:

```sh
bundle install
```

## Mount the Engine

In your `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  mount RailsLogViewer::Engine, at: '/logs'
end
```

The log viewer UI will be available at `/logs`.

## Configuration

Create an initializer at `config/initializers/rails_log_viewer.rb`:

```ruby
RailsLogViewer.configure do |c|
  # Required — authentication proc (see Security section)
  c.authenticate_with = ->(controller) { controller.current_user&.admin? }

  # Log source: :local or :cloudwatch
  c.source = :local

  # Lines returned per page
  c.lines_per_page = 500

  # Redact sensitive patterns from log output
  c.redact_patterns = [
    /password=\S+/,
    /token=\S+/,
    /Bearer\s+\S+/
  ]
end
```

### Configuration Reference

| Option | Type | Default | Description |
|---|---|---|---|
| `source` | Symbol | `:local` | Log source — `:local` or `:cloudwatch` |
| `authenticate_with` | Proc | `nil` | **Required.** Proc receiving the controller instance. Must return truthy to allow access. |
| `lines_per_page` | Integer | `500` | Number of log lines per page |
| `redact_patterns` | Array\<Regexp\> | `[]` | Patterns to replace with `[REDACTED]` in output |
| `aws_log_group` | String | `nil` | CloudWatch log group name |
| `aws_log_stream_prefix` | String | `nil` | Filter streams by prefix |
| `aws_region` | String | `ENV["AWS_REGION"]` | AWS region for CloudWatch |

## Local File Usage

The local backend reads from `Rails.root/log/production.log` by default. It uses `tail` and reverse file seeking to read from the end of the file without loading it entirely into memory.

```ruby
RailsLogViewer.configure do |c|
  c.authenticate_with = ->(controller) { controller.current_user&.admin? }
  c.source = :local
  c.lines_per_page = 200
  c.redact_patterns = [/api_key=\S+/]
end
```

## AWS CloudWatch Usage

```ruby
RailsLogViewer.configure do |c|
  c.authenticate_with = ->(controller) { controller.current_user&.admin? }
  c.source = :cloudwatch
  c.aws_log_group = '/ecs/my-app-production'
  c.aws_log_stream_prefix = 'web/'
  c.aws_region = 'us-east-1'
end
```

### Required IAM Permissions

The AWS credentials available to your application need the following permissions on the target log group:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:DescribeLogStreams",
        "logs:GetLogEvents",
        "logs:FilterLogEvents"
      ],
      "Resource": "arn:aws:logs:us-east-1:123456789:log-group:/ecs/my-app-production:*"
    }
  ]
}
```

Credentials are resolved via the standard AWS SDK chain: environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`), IAM instance role, ECS task role, or shared credentials file.

## Security

**Authentication is mandatory.** If `authenticate_with` is not configured, the engine raises `RailsLogViewer::ConfigurationError` on every request.

The proc receives the controller instance, giving you access to your application's authentication helpers:

```ruby
# Devise admin check
c.authenticate_with = ->(controller) { controller.current_user&.admin? }

# HTTP basic auth
c.authenticate_with = ->(controller) {
  controller.authenticate_or_request_with_http_basic do |user, pass|
    ActiveSupport::SecurityUtils.secure_compare(user, 'admin') &
    ActiveSupport::SecurityUtils.secure_compare(pass, Rails.application.credentials.log_viewer_password)
  end
}

# Environment-based restriction
c.authenticate_with = ->(_controller) { Rails.env.development? }
```

If the proc returns a falsy value, the engine responds with `403 Forbidden`.

**Redaction** — use `redact_patterns` to strip sensitive data from log output before it reaches the browser. Patterns are applied to every line via `gsub`.

**Recommendations:**
- Mount behind your application's existing authentication
- Use `redact_patterns` to strip tokens, passwords, and PII
- Restrict access to admin users in production
- Consider mounting at a non-obvious path in production

## UI Features

- Dark-themed interface optimized for log readability
- Log line colorization by severity (ERROR/FATAL, WARN, INFO, DEBUG)
- Muted styling for redacted lines
- Search with 400ms debounce
- Live Tail mode via Server-Sent Events
- CloudWatch stream selector dropdown
- Pagination with "Load older logs"
- Copy visible lines to clipboard
- Zero external dependencies — all CSS and JS inline

## Rake Tasks

Validate your configuration:

```sh
bin/rails rails_log_viewer:check_config
```

## Screenshots

*Screenshots coming soon.*

## License

MIT

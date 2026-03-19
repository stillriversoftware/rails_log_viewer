# Changelog

## 0.1.0

Initial release.

- Local log file backend with reverse file reading and timestamp parsing
- AWS CloudWatch Logs backend with cross-stream search via filter_log_events
- Amazon S3 backend for archived/rotated logs with gzip decompression
- Cursor-based pagination (byte offset for local, timestamp for CloudWatch, line index for S3)
- Time-range scoped queries with preset ranges (15m, 1h, 6h, 24h) and custom picker
- Severity filtering (ERROR, WARN, INFO, DEBUG) composable with search and time range
- Built-in redaction for passwords, tokens, API keys, credit cards, SSNs, AWS credentials
- User-configurable additional redaction patterns
- Mountable Rails Engine with isolated namespace
- Mandatory authentication via configurable proc
- Dark-themed log viewer UI with severity colorization
- Live Tail mode via Server-Sent Events with smart auto-scroll
- Search with 400ms debounce
- CloudWatch stream selector and S3 file selector dropdowns
- Copy to clipboard
- Rake task for configuration validation
- CI via GitHub Actions (Ruby 3.2, 3.3, 3.4)

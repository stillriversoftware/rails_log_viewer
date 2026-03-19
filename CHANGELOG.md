# Changelog

## 0.1.0

Initial release.

- Local log file backend with tail-based reading and reverse file search
- AWS CloudWatch Logs backend with stream listing, event reading, and filter search
- Mountable Rails Engine with isolated namespace
- Authentication enforcement via configurable proc
- Pattern-based log redaction
- Dark-themed log viewer UI with severity colorization
- Live Tail mode via Server-Sent Events
- Search with debounce
- Pagination support
- Copy to clipboard
- CloudWatch stream selector
- Rake task for configuration validation

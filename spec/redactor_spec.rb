require 'spec_helper'

RSpec.describe RailsLogViewer::Redactor do
  describe 'default patterns' do
    it 'redacts password parameters' do
      expect(described_class.redact_line('login password=hunter2 done')).to eq('login [REDACTED] done')
      expect(described_class.redact_line('user passwd=secret123')).to include('[REDACTED]')
      expect(described_class.redact_line('pwd=abc')).to include('[REDACTED]')
    end

    it 'redacts token parameters' do
      expect(described_class.redact_line('auth token=abc123xyz')).to include('[REDACTED]')
      expect(described_class.redact_line('access_token=eyJhbGci')).to include('[REDACTED]')
      expect(described_class.redact_line('api_token=sk-1234')).to include('[REDACTED]')
      expect(described_class.redact_line('refresh_token=rt_abc')).to include('[REDACTED]')
    end

    it 'redacts API keys' do
      expect(described_class.redact_line('api_key=AKIAIOSFODNN7')).to include('[REDACTED]')
      expect(described_class.redact_line('apikey=secret_value')).to include('[REDACTED]')
      expect(described_class.redact_line('secret_key=wJalrXUtnFEMI')).to include('[REDACTED]')
    end

    it 'redacts Authorization headers' do
      expect(described_class.redact_line('Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.abc')).to include('[REDACTED]')
      expect(described_class.redact_line('Authorization: Basic dXNlcjpwYXNz')).to include('[REDACTED]')
      expect(described_class.redact_line('Authorization: Token abc123')).to include('[REDACTED]')
    end

    it 'redacts standalone Bearer tokens' do
      expect(described_class.redact_line('Bearer eyJhbGciOiJIUzI1NiJ9')).to include('[REDACTED]')
    end

    it 'redacts credit card number patterns' do
      expect(described_class.redact_line('card 4111111111111111 charged')).to eq('card [REDACTED] charged')
      expect(described_class.redact_line('cc 4111-1111-1111-1111')).to include('[REDACTED]')
    end

    it 'redacts SSN patterns' do
      expect(described_class.redact_line('ssn 123-45-6789 found')).to eq('ssn [REDACTED] found')
    end

    it 'redacts AWS credentials' do
      expect(described_class.redact_line('aws_secret_access_key=wJalrXUtnFEMI/abc')).to include('[REDACTED]')
      expect(described_class.redact_line('aws_access_key_id=AKIAIOSFODNN7')).to include('[REDACTED]')
    end

    it 'redacts secret_key_base' do
      expect(described_class.redact_line('secret_key_base: abc123def456')).to include('[REDACTED]')
    end

    it 'redacts database URLs' do
      expect(described_class.redact_line('database_url=postgres://user:pass@host/db')).to include('[REDACTED]')
    end

    it 'does not redact normal text' do
      line = 'Started GET "/users" for 127.0.0.1 at 2026-03-19 10:00:00'
      expect(described_class.redact_line(line)).to eq(line)
    end
  end

  describe '.patterns' do
    it 'includes defaults when redact_defaults is true' do
      patterns = described_class.patterns
      expect(patterns.length).to be >= RailsLogViewer::Redactor::DEFAULT_PATTERNS.length
    end

    it 'excludes defaults when redact_defaults is false' do
      RailsLogViewer.configure { |c| c.redact_defaults = false }

      patterns = described_class.patterns
      expect(patterns).to be_empty
    end

    it 'merges user patterns with defaults' do
      custom = /my_custom_field=\S+/
      RailsLogViewer.configure { |c| c.redact_patterns = [custom] }

      patterns = described_class.patterns
      expect(patterns).to include(custom)
      expect(patterns.length).to eq(RailsLogViewer::Redactor::DEFAULT_PATTERNS.length + 1)
    end

    it 'applies user patterns in addition to defaults' do
      RailsLogViewer.configure do |c|
        c.redact_patterns = [/session_id=\S+/]
      end

      line = 'login password=hunter2 session_id=abc123'
      result = described_class.redact_line(line)

      expect(result).to eq('login [REDACTED] [REDACTED]')
    end
  end

  describe '.redact_lines' do
    it 'redacts hash entries with :message key' do
      lines = [
        { message: 'password=secret token=abc', timestamp: Time.now, severity: 'INFO' }
      ]
      result = described_class.redact_lines(lines)

      expect(result.first[:message]).not_to include('secret')
      expect(result.first[:message]).not_to include('abc')
      expect(result.first[:timestamp]).to be_a(Time)
    end

    it 'redacts plain string entries' do
      lines = ['password=secret data']
      result = described_class.redact_lines(lines)

      expect(result.first).to include('[REDACTED]')
      expect(result.first).not_to include('secret')
    end

    it 'returns lines unchanged when no patterns match' do
      RailsLogViewer.configure { |c| c.redact_defaults = false }

      lines = [{ message: 'normal log line', severity: 'INFO' }]
      result = described_class.redact_lines(lines)

      expect(result.first[:message]).to eq('normal log line')
    end
  end
end

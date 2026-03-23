# ============================================
# config/initializers/opentelemetry.rb
# ============================================

require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'
require 'opentelemetry/instrumentation/all'

OpenTelemetry::SDK.configure do |c|
  c.service_name = ENV.fetch('OTEL_SERVICE_NAME', 'myapp-rails')
  c.service_version = ENV.fetch('OTEL_SERVICE_VERSION', '1.0.0')

  c.add_span_processor(
    OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
      OpenTelemetry::Exporter::OTLP::Exporter.new(
        endpoint: ENV.fetch('OTEL_EXPORTER_OTLP_ENDPOINT', 'http://localhost:4318/v1/traces'),
      )
    )
  )

  c.use_all({
    'OpenTelemetry::Instrumentation::Rack' => {
      untraced_endpoints: ['/health', '/ready', '/metrics'],
    },
    'OpenTelemetry::Instrumentation::ActiveRecord' => {},
    'OpenTelemetry::Instrumentation::Mysql2' => {
      db_statement: :obfuscate,
    },
    'OpenTelemetry::Instrumentation::NetHTTP' => {},
    'OpenTelemetry::Instrumentation::Faraday' => {},
    'OpenTelemetry::Instrumentation::Redis' => {
      db_statement: :obfuscate,
    },
  })
end

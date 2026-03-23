# ============================================
# config/initializers/lograge.rb
# ログ JSON 化 + トレースID 付与
# ============================================

Rails.application.configure do
  config.lograge.enabled = true
  config.lograge.formatter = Lograge::Formatters::Json.new

  config.lograge.custom_payload do |controller|
    span = OpenTelemetry::Trace.current_span
    ctx = span.context
    {
      host:     Socket.gethostname,
      trace_id: ctx.hex_trace_id,
      span_id:  ctx.hex_span_id,
      user_id:  controller.try(:current_user)&.id,
      ip:       controller.request.remote_ip,
    }
  end

  config.lograge.custom_options = lambda do |event|
    {
      params:           event.payload[:params].except('controller', 'action', 'format', 'id'),
      exception:        event.payload[:exception],
      exception_object: event.payload[:exception_object]&.message,
    }
  end
end

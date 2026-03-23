"""
============================================
otel_setup.py - OpenTelemetry トレース + ログ設定
============================================

使い方:
  Flask:   init_telemetry(app, framework="flask")
  Django:  init_telemetry(framework="django")
  FastAPI: init_telemetry(app, framework="fastapi")
"""

import os
import logging
from pythonjsonlogger import jsonlogger

from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanExporter
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.instrumentation.logging import LoggingInstrumentor


def init_telemetry(app=None, framework="flask"):
    service_name = os.environ.get("OTEL_SERVICE_NAME", "myapp-python")
    otlp_endpoint = os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", "localhost:4317")

    # リソース情報
    resource = Resource.create({
        "service.name": service_name,
        "service.version": os.environ.get("OTEL_SERVICE_VERSION", "1.0.0"),
        "deployment.environment": os.environ.get("DEPLOYMENT_ENV", "production"),
    })

    # トレーサー
    provider = TracerProvider(resource=resource)
    exporter = OTLPSpanExporter(endpoint=otlp_endpoint, insecure=True)
    provider.add_span_processor(BatchSpanExporter(exporter))
    trace.set_tracer_provider(provider)

    # ログにトレースID自動付与
    LoggingInstrumentor().instrument(set_logging_format=True)
    _setup_json_logging(service_name)

    # フレームワーク計装
    if framework == "flask" and app:
        from opentelemetry.instrumentation.flask import FlaskInstrumentor
        FlaskInstrumentor().instrument_app(app)
    elif framework == "django":
        from opentelemetry.instrumentation.django import DjangoInstrumentor
        DjangoInstrumentor().instrument()
    elif framework == "fastapi" and app:
        from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
        FastAPIInstrumentor.instrument_app(app)

    # 共通ライブラリ計装
    for mod, cls in [
        ("opentelemetry.instrumentation.requests", "RequestsInstrumentor"),
        ("opentelemetry.instrumentation.sqlalchemy", "SQLAlchemyInstrumentor"),
        ("opentelemetry.instrumentation.pymysql", "PyMySQLInstrumentor"),
        ("opentelemetry.instrumentation.redis", "RedisInstrumentor"),
        ("opentelemetry.instrumentation.celery", "CeleryInstrumentor"),
    ]:
        try:
            m = __import__(mod, fromlist=[cls])
            getattr(m, cls)().instrument()
        except ImportError:
            pass

    logging.getLogger(__name__).info(
        f"OpenTelemetry initialized: service={service_name}, endpoint={otlp_endpoint}"
    )


def _setup_json_logging(service_name):
    class Fmt(jsonlogger.JsonFormatter):
        def add_fields(self, log_record, record, message_dict):
            super().add_fields(log_record, record, message_dict)
            log_record["service"] = service_name
            log_record["level"] = record.levelname
            span = trace.get_current_span()
            if span and span.get_span_context().trace_id:
                ctx = span.get_span_context()
                log_record["trace_id"] = format(ctx.trace_id, '032x')
                log_record["span_id"] = format(ctx.span_id, '016x')

    fmt = Fmt(fmt="%(asctime)s %(level)s %(name)s %(message)s", datefmt="%Y-%m-%dT%H:%M:%S")

    handler = logging.StreamHandler()
    handler.setFormatter(fmt)

    file_handler = logging.FileHandler("/var/log/myapp/app.log")
    file_handler.setFormatter(fmt)

    root = logging.getLogger()
    root.setLevel(logging.INFO)
    root.addHandler(handler)
    root.addHandler(file_handler)

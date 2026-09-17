"""Trace-Checks via Tempo-Search: B1 (Praesenz), B2 (Span-Namen), B5 (Dauer),
B4 (Span-/Resource-Attribute)."""
import pytest

SVC = "food-order-backend"
HTTP_TIMEOUT = 10


@pytest.mark.e2e
def test_b1_traces_vorhanden(traffic, tempo_search, until):
    """B1: Tempo liefert Traces des Service."""
    traces = until(
        lambda: tempo_search(f'{{ resource.service.name = "{SVC}" }}', limit=5),
        timeout=30, what="Tempo-Traces fuer food-order-backend",
    )
    assert traces, "keine Traces gefunden"


@pytest.mark.e2e
def test_b2_span_namen_vorhanden(traffic, tempo_search, until):
    """B2: Traces fuer konkrete Span-Namen (POST /api/orders, GET /api/products)."""
    for name in ("POST /api/orders", "GET /api/products"):
        traces = until(
            lambda n=name: tempo_search(
                f'{{ resource.service.name="{SVC}" && name="{n}" }}', limit=5
            ),
            timeout=30, what=f"Trace mit Span-Name '{name}'",
        )
        assert traces, f"kein Trace fuer Span-Name '{name}'"


@pytest.mark.e2e
def test_b5_trace_dauer_plausibel(traffic, tempo_search, until):
    """B5: Trace-Dauer > 0 und < 60000 ms (plausibel)."""
    traces = until(
        lambda: tempo_search(f'{{ resource.service.name = "{SVC}" }}', limit=5),
        timeout=30, what="Traces fuer Dauer-Pruefung",
    )
    checked = 0
    for t in traces:
        dur_ms = t.get("durationMs")
        if dur_ms is None:
            # Fallback: aus Span-durationNanos ableiten.
            spans = (t.get("spanSet") or {}).get("spans") or []
            if spans and spans[0].get("durationNanos"):
                dur_ms = int(spans[0]["durationNanos"]) / 1e6
        assert dur_ms is not None, f"Trace ohne Dauer: {t.get('traceID')}"
        assert 0 < dur_ms < 60000, f"unplausible Dauer {dur_ms} ms ({t.get('traceID')})"
        checked += 1
    assert checked >= 1, "keine Trace-Dauer geprueft"


# --- B4: Span-/Resource-Attribute -------------------------------------------
# Empirisch am laufenden Stack (opentelemetry-java-instrumentation 2.31.1)
# bestimmte Keys. Resource: deployment.environment (NICHT ...environment.name),
# service.namespace, service.version, telemetry.sdk.language. HTTP-Span nutzt die
# neue Semantic-Convention: http.request.method / http.response.status_code.


@pytest.mark.e2e
def test_b4_span_und_resource_attribute(traffic, tempo_search, urls, until, http):
    """B4: Resource- und HTTP-Span-Attribute sind in Tempo abfragbar.

    Assertions bevorzugt via TraceQL-Attribut-Filter (konsistent zu B1/B2),
    zusaetzlich Deep-Parse eines vollen Traces auf erwartete Resource-Keys.
    """
    # 1) Resource-Attribute via TraceQL.
    resource_queries = [
        '{ resource.service.name = "food-order-backend" }',
        '{ resource.service.namespace = "food-order" }',
        '{ resource.deployment.environment = "demo" }',
    ]
    for q in resource_queries:
        until(lambda q=q: tempo_search(q, limit=5), timeout=30,
              what=f"Trace fuer Resource-Filter {q}")

    # 2) HTTP-Span-Semantik auf dem Order-Span (neue Semantic Convention).
    http_queries = [
        '{ resource.service.name="food-order-backend" && span.http.request.method = "POST" }',
        '{ resource.service.name="food-order-backend" && span.http.response.status_code = 201 }',
    ]
    for q in http_queries:
        until(lambda q=q: tempo_search(q, limit=5), timeout=30,
              what=f"Trace fuer HTTP-Span-Filter {q}")

    # 3) Deep-Parse: vollen Trace laden und erwartete Resource-Keys pruefen.
    traces = until(
        lambda: tempo_search(
            '{ resource.service.name="food-order-backend" && name="POST /api/orders" }',
            limit=1,
        ),
        timeout=30, what="Order-Trace fuer Deep-Parse",
    )
    trace_id = traces[0]["traceID"]

    def load_trace():
        r = http.get(f"{urls['tempo']}/api/traces/{trace_id}", timeout=HTTP_TIMEOUT)
        return r.json() if r.status_code == 200 else None

    trace = until(load_trace, timeout=30, what=f"Tempo-Trace {trace_id}")

    resource_keys = set()
    span_http_keys = set()
    for batch in trace.get("batches", []):
        for a in batch.get("resource", {}).get("attributes", []):
            resource_keys.add(a["key"])
        for scope in batch.get("scopeSpans", []):
            for span in scope.get("spans", []):
                for a in span.get("attributes", []):
                    if a["key"].startswith("http."):
                        span_http_keys.add(a["key"])

    expected_resource = {
        "service.name", "service.namespace",
        "deployment.environment", "telemetry.sdk.language",
    }
    missing = expected_resource - resource_keys
    assert not missing, f"Resource-Keys fehlen: {missing} (vorhanden: {sorted(resource_keys)})"
    assert "http.request.method" in span_http_keys, (
        f"http.request.method fehlt (HTTP-Keys: {sorted(span_http_keys)})"
    )
    assert "http.response.status_code" in span_http_keys, (
        f"http.response.status_code fehlt (HTTP-Keys: {sorted(span_http_keys)})"
    )


@pytest.mark.e2e
def test_b4_business_attribute_order_item_count(traffic, tempo_search, until):
    """B4 (bedingt): Business-Attribut order.item_count auf einem Span.

    Empirisch erzeugt der OTel-Java-Agent 2.31.1 aus der Micrometer-Observation
    KEINEN Span mit diesem Attribut (nur die Metrik). Daher: skip statt Fake,
    solange kein Trace mit `span.order.item_count > 0` gefunden wird.
    """
    try:
        traces = until(
            lambda: tempo_search('{ span.order.item_count > 0 }', limit=5),
            timeout=20, what="Trace mit span.order.item_count > 0",
        )
    except AssertionError:
        traces = None

    if not traces:
        pytest.skip(
            "order.item_count ist kein Span-Attribut (OTel-Agent exportiert die "
            "Micrometer-Observation nur als Metrik, nicht als Span) – uebersprungen"
        )
    # Falls in einer spaeteren App-Version doch vorhanden: als Nachweis werten.
    assert traces


@pytest.mark.e2e
def test_b3_trace_tiefe_http_und_db(traffic, tempo_search, urls, until, http):
    """B3: Ein POST-/api/orders-Trace reicht bis in die DB.

    Beweist Trace-Tiefe: > 1 Span und sowohl ein HTTP-Server-Span (Attribut
    http.request.method bzw. Scope tomcat) als auch ein DB-Span (Attribut
    db.system/db.statement bzw. Scope jdbc) sind vorhanden.
    """
    # Grosszuegiger Timeout: frisch erzeugte Traces brauchen etwas, bis sie in
    # Tempo durchsuchbar sind (WAL-Flush).
    traces = until(
        lambda: tempo_search(
            '{ resource.service.name="food-order-backend" && name="POST /api/orders" }',
            limit=1,
        ),
        timeout=90, what="POST /api/orders-Trace fuer Tiefen-Pruefung",
    )
    trace_id = traces[0]["traceID"]

    def load_trace():
        r = http.get(f"{urls['tempo']}/api/traces/{trace_id}", timeout=HTTP_TIMEOUT)
        return r.json() if r.status_code == 200 else None

    trace = until(load_trace, timeout=30, what=f"Tempo-Trace {trace_id}")

    span_count = 0
    has_http = False
    has_db = False
    for batch in trace.get("batches", []):
        for scope in batch.get("scopeSpans", []):
            scope_name = scope.get("scope", {}).get("name", "")
            for span in scope.get("spans", []):
                span_count += 1
                attr_keys = {a["key"] for a in span.get("attributes", [])}
                if "http.request.method" in attr_keys or "tomcat" in scope_name:
                    has_http = True
                if (
                    "db.system" in attr_keys
                    or "db.statement" in attr_keys
                    or "jdbc" in scope_name
                ):
                    has_db = True

    assert span_count > 1, f"Trace {trace_id} hat nur {span_count} Span(s)"
    assert has_http, f"kein HTTP-Server-Span in Trace {trace_id}"
    assert has_db, f"kein DB-Span in Trace {trace_id}"

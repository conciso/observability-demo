"""D1: Trace<->Log-Korrelation ueber den eindeutigen customer-Marker."""
import base64
import binascii

import pytest

SVC = "food-order-backend"
HTTP_TIMEOUT = 10


@pytest.mark.e2e
def test_d1_trace_log_korrelation(traffic, loki_query_range, urls, until, http):
    """D1: Aus der 'Created order'-Logzeile des eindeutigen Kunden die trace_id
    lesen und in Tempo denselben Trace (mit Span POST /api/orders) wiederfinden.
    """
    customer = traffic["customer"]

    # 1) In Loki die korrelierten Logzeilen des eindeutigen Kunden finden.
    def find_trace_id():
        streams = loki_query_range(
            f'{{service_name="{SVC}"}} |= "{customer}"', limit=20
        )
        for s in streams:
            labels = s.get("stream", {})
            tid = labels.get("trace_id")
            if not tid:
                continue
            for _ts, line in s.get("values", []):
                if "Created order" in line:
                    return tid
        return None

    trace_id = until(
        find_trace_id, timeout=30,
        what=f"trace_id der 'Created order'-Zeile fuer {customer}",
    )
    assert trace_id, "keine trace_id aus Log ermittelt"

    # 2) In Tempo denselben Trace laden und Span POST /api/orders verifizieren.
    def load_trace():
        r = http.get(f"{urls['tempo']}/api/traces/{trace_id}", timeout=HTTP_TIMEOUT)
        if r.status_code != 200:
            return None
        return r.json()

    trace = until(
        load_trace, timeout=30, what=f"Tempo-Trace {trace_id}",
    )

    # Span-Namen aus dem OTLP-Trace-JSON einsammeln.
    span_names = []
    found_trace_id = None
    for batch in trace.get("batches", []):
        for scope in batch.get("scopeSpans", []):
            for span in scope.get("spans", []):
                span_names.append(span.get("name", ""))
                found_trace_id = span.get("traceId") or found_trace_id

    assert span_names, f"Trace {trace_id} enthaelt keine Spans"
    assert any("POST /api/orders" in n for n in span_names), (
        f"Span 'POST /api/orders' fehlt in Trace {trace_id}: {span_names}"
    )
    # Gleiche traceID ueber Log und Tempo. Das OTLP-JSON von /api/traces liefert
    # die traceId Base64-kodiert -> nach Hex normalisieren, dann vergleichen.
    if found_trace_id:
        try:
            tempo_hex = binascii.hexlify(base64.b64decode(found_trace_id)).decode()
        except (binascii.Error, ValueError):
            tempo_hex = found_trace_id.replace("-", "")
        assert tempo_hex.lower() == trace_id.lower(), (
            f"traceID-Mismatch: log={trace_id} tempo={found_trace_id} (hex={tempo_hex})"
        )

"""Log-Checks via Loki: C1 (Label), C2 (Inhalt), C3 (trace/span),
C4 (Resource-Labels), C5 (Severity)."""
import pytest

SVC = "food-order-backend"
HTTP_TIMEOUT = 10


@pytest.mark.smoke
def test_c1_service_name_label(urls, until, http):
    """C1: Loki kennt das Label service_name=food-order-backend."""
    def check():
        r = http.get(
            f"{urls['loki']}/loki/api/v1/label/service_name/values", timeout=HTTP_TIMEOUT
        )
        r.raise_for_status()
        return SVC in r.json().get("data", [])

    until(check, timeout=30, what=f"Loki-Label service_name={SVC}")


@pytest.mark.e2e
def test_c2_created_order_logzeile(traffic, loki_query_range, until):
    """C2: Es existiert eine 'Created order'-Logzeile (nach Traffic)."""
    def check():
        streams = loki_query_range(f'{{service_name="{SVC}"}}', limit=50)
        for s in streams:
            for _ts, line in s.get("values", []):
                if "Created order" in line:
                    return True
        return False

    until(check, timeout=30, what="Loki-Logzeile 'Created order'")


@pytest.mark.e2e
def test_c3_trace_und_span_id_labels(traffic, loki_query_range, until):
    """C3: Stream-Labels tragen nicht-leere trace_id UND span_id."""
    def check():
        streams = loki_query_range(f'{{service_name="{SVC}"}} | trace_id != ""', limit=10)
        for s in streams:
            labels = s.get("stream", {})
            if labels.get("trace_id") and labels.get("span_id"):
                return labels
        return None

    labels = until(check, timeout=30, what="Loki-Stream mit trace_id & span_id")
    assert labels["trace_id"], "trace_id leer"
    assert labels["span_id"], "span_id leer"


@pytest.mark.smoke
def test_c4_resource_labels(traffic, loki_query_range, until):
    """C4: Stream-Labels enthalten Resource-Attribute."""
    expected = ("service_namespace", "deployment_environment", "service_version")

    def check():
        streams = loki_query_range(f'{{service_name="{SVC}"}}', limit=10)
        for s in streams:
            labels = s.get("stream", {})
            if all(labels.get(k) for k in expected):
                return labels
        return None

    labels = until(check, timeout=30, what=f"Loki-Resource-Labels {expected}")
    for k in expected:
        assert labels.get(k), f"Resource-Label fehlt/leer: {k}"


@pytest.mark.smoke
def test_c5_severity_vorhanden(traffic, loki_query_range, until):
    """C5: severity_text/detected_level aus bekannter Menge."""
    allowed = {"TRACE", "DEBUG", "INFO", "WARN", "WARNING", "ERROR", "FATAL"}

    def check():
        streams = loki_query_range(f'{{service_name="{SVC}"}}', limit=20)
        for s in streams:
            labels = s.get("stream", {})
            sev = (labels.get("severity_text") or labels.get("detected_level") or "").upper()
            if sev in allowed:
                return sev
        return None

    sev = until(check, timeout=30, what="Loki-Severity-Label")
    assert sev in allowed, f"unerwartete Severity: {sev}"

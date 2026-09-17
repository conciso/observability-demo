"""Metrik-Checks am Actuator-Endpoint: A1 (Format), A2 (Business), A6 (JVM),
A4 (fehlgeschlagene Bestellung zaehlt nicht)."""
import re

import pytest

HTTP_TIMEOUT = 10


def _sum_series_value(text, metric):
    """Summiert die Werte aller Serien eines Metriknamens aus dem Actuator-Text."""
    total = 0.0
    found = False
    pat = re.compile(r"^" + re.escape(metric) + r"(\{[^}]*\})?\s+([0-9eE.+-]+)$")
    for line in text.splitlines():
        m = pat.match(line.strip())
        if m:
            total += float(m.group(2))
            found = True
    return total if found else None


@pytest.mark.smoke
def test_a1_actuator_prometheus_parsebar(prom_series):
    """A1: /actuator/prometheus liefert 200 und parsebares Textformat."""
    names, raw = prom_series()
    assert "# HELP" in raw, "keine HELP-Zeilen im Prometheus-Text"
    assert len(names) >= 1, "keine parsebaren Serien gefunden"


@pytest.mark.smoke
def test_a2_business_metrics_vorhanden(traffic, prom_series, until):
    """A2: Business-Serien vorhanden (nach erzeugtem Traffic)."""
    expected = [
        "orders_created_total",
        "order_value_euros_count",
        "order_value_euros_sum",
        "order_value_euros_bucket",
    ]

    def check():
        names, _ = prom_series()
        return all(e in names for e in expected)

    until(check, timeout=30, what=f"Business-Metriken {expected}")


@pytest.mark.smoke
def test_a6_jvm_metrics_vorhanden(prom_series):
    """A6: JVM-/Prozess-Serien vorhanden."""
    names, _ = prom_series()
    for e in ("jvm_memory_used_bytes", "jvm_threads_live_threads", "process_cpu_usage"):
        assert e in names, f"JVM-Metrik fehlt: {e}"


@pytest.mark.e2e
def test_a4_fehlgeschlagene_bestellung_zaehlt_nicht(urls, prom_text, http):
    """A4: Eine fehlgeschlagene Bestellung erhoeht orders_created_total NICHT.

    Deterministisch ueber den Actuator-Textendpoint (kein Scrape-Delay). Es wird
    bewusst KEINE gueltige Bestellung im Test abgesetzt, damit der Vor/Nach-
    Vergleich exakt bleibt.
    """
    v0 = _sum_series_value(prom_text(), "orders_created_total")
    assert v0 is not None, "orders_created_total nicht im Actuator-Text gefunden"

    bad = http.post(
        f"{urls['backend']}/api/orders",
        json={"customerName": "a4-invalid", "items": [{"productId": 99999, "quantity": 1}]},
        timeout=HTTP_TIMEOUT,
    )
    assert bad.status_code == 404, f"ungueltige Bestellung erwartet 404, war {bad.status_code}"

    v1 = _sum_series_value(prom_text(), "orders_created_total")
    assert v1 == v0, f"orders_created_total veraendert durch fehlgeschlagene Bestellung: {v0} -> {v1}"

"""PromQL-Testblock: rechnende Queries gegen den laufenden Prometheus.

Scrape-Intervall = 15s -> grosszuegige Timeouts (~60s). Alle Waits ueber until().
Keine absoluten Werte ausser via Delta (A7) bzw. "> 0 / enthaelt 201".
"""
import math

import pytest

SVC = "food-order-backend"


@pytest.mark.e2e
def test_a7_scrape_pfad_delta(urls, promql, run_id, place_orders, until):
    """A7: Beweist den Scrape-Pfad Endpoint->Prometheus ueber ein Delta.

    Setzt M gueltige Bestellungen ab und wartet, bis der Zaehler in Prometheus
    um >= M gestiegen ist (>= statt ==, da paralleler Traffic moeglich).
    """
    customer = f"obs-promql-{run_id}"
    M = 2

    # Ausgangswert (until, bis ueberhaupt ein Wert in Prometheus vorhanden ist).
    v0 = until(
        lambda: promql.instant_sum("orders_created_total"),
        timeout=60, what="Startwert orders_created_total in Prometheus",
    )
    assert v0 is not None

    # M gueltige Bestellungen absetzen.
    placed = place_orders(customer, count=M, product_id=1, quantity=2)
    assert placed == M

    # Warten, bis Prometheus den erhoehten Zaehler gescrapt hat.
    def delta_reached():
        v = promql.instant_sum("orders_created_total")
        return v if v >= v0 + M else None

    v1 = until(delta_reached, timeout=60, what=f"orders_created_total >= {v0}+{M}")
    assert v1 - v0 >= M, f"Delta {v1 - v0} < {M}"


@pytest.mark.e2e
def test_rate_http_requests(traffic, promql, until):
    """rate(): Gesamt-Request-Rate > 0 und rate fuer /api/orders nicht leer."""
    q_total = "sum(rate(http_server_requests_seconds_count[5m]))"
    total = until(
        lambda: (lambda v: v if v > 0 else None)(promql.instant_sum(q_total)),
        timeout=60, what=f"{q_total} > 0",
    )
    assert total > 0

    q_orders = 'rate(http_server_requests_seconds_count{uri="/api/orders"}[5m])'
    res = until(
        lambda: promql.instant(q_orders) or None,
        timeout=60, what=f"{q_orders} nicht leer",
    )
    assert res, "rate fuer /api/orders leer"


@pytest.mark.e2e
def test_histogram_quantile_p95(promql, run_id, place_orders, until):
    """histogram_quantile p95 des Bestellwerts: genau ein Vektor-Element,
    endlich und > 0. Setzt frische Bestellungen ab, damit die Buckets im
    5m-rate-Fenster ansteigen (sonst NaN).
    """
    customer = f"obs-promql-p95-{run_id}"
    place_orders(customer, count=3, product_id=1, quantity=2)

    q = "histogram_quantile(0.95, sum by (le) (rate(order_value_euros_bucket[5m])))"

    def finite_positive():
        res = promql.instant(q)
        if not res or len(res) != 1:
            return None
        _labels, val = res[0]
        if math.isnan(val) or math.isinf(val) or val <= 0:
            return None
        return val

    val = until(finite_positive, timeout=60, what=f"{q} endlich und > 0")
    assert val > 0 and math.isfinite(val)


@pytest.mark.e2e
def test_sum_by_status(traffic, promql, until):
    """sum by(status) fuer /api/orders enthaelt status=201 mit Wert >= 1."""
    q = 'sum by (status) (http_server_requests_seconds_count{uri="/api/orders"})'

    def has_201():
        res = promql.instant(q)
        for labels, val in res:
            if labels.get("status") == "201" and val >= 1:
                return val
        return None

    val = until(has_201, timeout=60, what=f"{q} enthaelt status=201 >= 1")
    assert val >= 1


@pytest.mark.e2e
def test_avg_order_value_expr(traffic, promql, until):
    """Ø-Bestellwert als PromQL-Ausdruck: endlich und > 0."""
    q = "order_value_euros_sum / order_value_euros_count"

    def finite_positive():
        res = promql.instant(q)
        for _labels, val in res:
            if math.isfinite(val) and val > 0:
                return val
        return None

    val = until(finite_positive, timeout=60, what=f"{q} endlich und > 0")
    assert val > 0 and math.isfinite(val)

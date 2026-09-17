"""G3: Freshness – juengste Telemetrie in Prometheus, Tempo und Loki ist aktuell."""
import time

import pytest

SVC = "food-order-backend"
HTTP_TIMEOUT = 10
MAX_AGE_S = 10 * 60  # 10 Minuten


@pytest.mark.smoke
def test_g3_freshness_prometheus(traffic, urls, until, http):
    """Prometheus: Zeitstempel von orders_created_total ist juenger als MAX_AGE."""
    def check():
        r = http.get(
            f"{urls['prom']}/api/v1/query",
            params={"query": "orders_created_total"}, timeout=HTTP_TIMEOUT,
        )
        r.raise_for_status()
        result = r.json()["data"]["result"]
        if not result:
            return None
        ts = max(float(s["value"][0]) for s in result)  # epoch Sekunden
        return ts if (time.time() - ts) < MAX_AGE_S else None

    until(check, timeout=30, what="frischer Prometheus-Wert (orders_created_total)")


@pytest.mark.smoke
def test_g3_freshness_tempo(traffic, tempo_search, until):
    """Tempo: neuester Trace startet innerhalb der letzten MAX_AGE Sekunden."""
    def check():
        traces = tempo_search(f'{{ resource.service.name = "{SVC}" }}', limit=20)
        if not traces:
            return None
        newest = max(int(t.get("startTimeUnixNano", "0")) for t in traces)
        age = time.time() - newest / 1e9
        return newest if age < MAX_AGE_S else None

    until(check, timeout=30, what="frischer Tempo-Trace")


@pytest.mark.smoke
def test_g3_freshness_loki(traffic, loki_query_range, until):
    """Loki: neueste Logzeile liegt innerhalb der letzten MAX_AGE Sekunden."""
    def check():
        streams = loki_query_range(f'{{service_name="{SVC}"}}', limit=10, direction="backward")
        newest_ns = 0
        for s in streams:
            for ts, _line in s.get("values", []):
                newest_ns = max(newest_ns, int(ts))
        if newest_ns == 0:
            return None
        age = time.time() - newest_ns / 1e9
        return newest_ns if age < MAX_AGE_S else None

    until(check, timeout=30, what="frische Loki-Logzeile")

"""Infrastruktur-Checks: Prometheus-Targets (A8) und Grafana/Datasources (F2)."""
import pytest

HTTP_TIMEOUT = 10


@pytest.mark.smoke
def test_a8_prometheus_targets_up(urls, cfg, http):
    """A8: Alle aktiven Prometheus-Targets sind 'up'.

    node-exporter nur strikt pruefen, wenn STRICT_NODE_EXPORTER=true.
    """
    r = http.get(f"{urls['prom']}/api/v1/targets", timeout=HTTP_TIMEOUT)
    r.raise_for_status()
    targets = r.json()["data"]["activeTargets"]
    assert targets, "keine aktiven Prometheus-Targets"

    down = []
    for t in targets:
        job = t["labels"].get("job", "?")
        if t["health"] != "up":
            if job == "node-exporter" and not cfg["strict_node_exporter"]:
                continue  # toleriert (Docker-Desktop-Host etc.)
            down.append(f"{job}={t['health']}")
    assert not down, f"Targets nicht 'up': {down}"


@pytest.mark.smoke
def test_f2_grafana_health_and_datasources(urls, grafana_auth, http):
    """F2: Grafana lebt, Datasources Prometheus/Loki/Tempo sind provisioniert,
    Datasource-Health tolerant geprueft (primaer: /api/health + Existenz).
    """
    # Grafana-Health (ohne Auth).
    h = http.get(f"{urls['grafana']}/api/health", timeout=HTTP_TIMEOUT)
    assert h.status_code == 200, f"Grafana /api/health = {h.status_code}"

    # Datasources vorhanden.
    ds = http.get(
        f"{urls['grafana']}/api/datasources", auth=grafana_auth, timeout=HTTP_TIMEOUT
    )
    assert ds.status_code == 200, f"/api/datasources = {ds.status_code}"
    types = {d["type"] for d in ds.json()}
    for expected in ("prometheus", "loki", "tempo"):
        assert expected in types, f"Datasource-Typ fehlt: {expected} (vorhanden: {types})"

    # Datasource-Health je uid – tolerant (nur pruefen, falls Endpoint 200 liefert).
    for uid in ("prometheus", "loki", "tempo"):
        resp = http.get(
            f"{urls['grafana']}/api/datasources/uid/{uid}/health",
            auth=grafana_auth, timeout=HTTP_TIMEOUT,
        )
        if resp.status_code == 200:
            status = resp.json().get("status", "")
            assert status.upper() == "OK", f"Datasource {uid} health status = {status}"

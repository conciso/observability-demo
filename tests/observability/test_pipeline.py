"""telemetrygen-Pipeline-Tests -> Collector -> Tempo/Loki/Prometheus.

E1: Traces -> Tempo, E2: Logs -> Loki, E3: Metrics -> Prometheus.
"""
import shutil
import subprocess

import pytest

TELEMETRYGEN_IMAGE = (
    "ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen"
)


def _find_monitoring_network():
    """Ermittelt den Compose-Netzwerknamen (i.d.R. monitoring_monitoring)."""
    out = subprocess.run(
        ["docker", "network", "ls", "--format", "{{.Name}}"],
        capture_output=True, text=True, timeout=20,
    )
    if out.returncode != 0:
        return None
    nets = [n for n in out.stdout.split() if "monitoring" in n]
    # Bevorzugt das Compose-Netz mit Praefix, sonst das erste Treffer.
    for n in nets:
        if n.endswith("_monitoring"):
            return n
    return nets[0] if nets else None


def _pipeline_network_or_skip(cfg):
    """Gemeinsames Gate fuer E1/E2/E3: RUN_TELEMETRYGEN, docker, Netz."""
    if not cfg["run_telemetrygen"]:
        pytest.skip("RUN_TELEMETRYGEN=false – Pipeline-Test uebersprungen")
    if shutil.which("docker") is None:
        pytest.skip("docker nicht verfuegbar – Pipeline-Test uebersprungen")
    network = _find_monitoring_network()
    if not network:
        pytest.skip("Compose-Netz 'monitoring' nicht gefunden – Pipeline-Test uebersprungen")
    return network


def _run_telemetrygen(network, signal, service, extra):
    """Fuehrt telemetrygen fuer ein Signal aus; skippt bei Fehler (Image/Netz)."""
    cmd = [
        "docker", "run", "--rm", "--network", network, TELEMETRYGEN_IMAGE,
        signal, "--otlp-endpoint", "otel-collector:4317", "--otlp-insecure",
        "--service", service,
    ] + extra
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    if proc.returncode != 0:
        pytest.skip(
            f"telemetrygen {signal} konnte nicht ausgefuehrt werden (Image/Netz?): "
            + (proc.stderr.strip()[-300:] or proc.stdout.strip()[-300:])
        )


@pytest.mark.pipeline
def test_e1_telemetrygen_traces(cfg, run_id, tempo_search, until):
    """E1: telemetrygen schickt Traces an den Collector; Tempo findet sie."""
    network = _pipeline_network_or_skip(cfg)
    service = f"telemetrygen-ci-{run_id}"
    _run_telemetrygen(network, "traces", service, ["--traces", "5"])

    traces = until(
        lambda: tempo_search(f'{{ resource.service.name = "{service}" }}', limit=5),
        timeout=30, what=f"Tempo-Traces fuer {service}",
    )
    assert traces, f"keine telemetrygen-Traces fuer {service} in Tempo"


@pytest.mark.pipeline
def test_e2_telemetrygen_logs(cfg, run_id, loki_query_range, until):
    """E2: telemetrygen schickt Logs an den Collector; Loki findet sie.

    Empirisch: die Logs erscheinen in Loki mit dem Label
    service_name=telemetrygen-logs-<run_id> (aus --service).
    """
    network = _pipeline_network_or_skip(cfg)
    service = f"telemetrygen-logs-{run_id}"
    _run_telemetrygen(
        network, "logs", service, ["--logs", "5", "--body", f"e2e-log-{run_id}"]
    )

    def find_logs():
        streams = loki_query_range(f'{{service_name="{service}"}}', limit=10)
        return streams or None

    streams = until(find_logs, timeout=60, what=f"Loki-Logs fuer {service}")
    assert streams, f"keine telemetrygen-Logs fuer {service} in Loki"


@pytest.mark.pipeline
def test_e3_telemetrygen_metrics(cfg, run_id, promql, until):
    """E3: telemetrygen schickt Metriken an den Collector; Prometheus scrapt sie.

    Empirisch: der Collector exponiert die Metrik als `gen_total`; der
    service.name landet als Label `exported_job` (Prometheus benennt das vom
    Collector gelieferte `job` um, da der Scrape-Job selbst `otel-collector` heisst).
    """
    network = _pipeline_network_or_skip(cfg)
    service = f"telemetrygen-metrics-{run_id}"
    _run_telemetrygen(
        network, "metrics", service, ["--metrics", "5", "--metric-type", "Sum"]
    )

    query = f'gen_total{{exported_job="{service}"}}'

    def present():
        res = promql.instant(query)
        return res or None

    # Grosszuegiger Timeout wegen 15s-Scrape-Intervall.
    res = until(present, timeout=60, what=f"Prometheus-Metrik {query}")
    assert res, f"telemetrygen-Metrik {query} nicht in Prometheus"

# Observability-Black-Box-Suite ("Quick-First-Suite")

Black-Box-Tests, die die **Telemetrie des laufenden Stacks** ausschliesslich ueber
die Query-APIs pruefen (Backend, Prometheus, Tempo, Loki, Grafana). Es wird **kein
App-Quellcode** angefasst. Der noetige Traffic wird von der Suite selbst erzeugt.

## Vorbedingung

Der komplette Stack **laeuft und ist healthy** (`docker-compose.yml` im Projektwurzel,
inkl. `node-exporter` via Override):

```bash
# im Projektwurzel
docker compose up -d
docker compose ps        # alle Container healthy/running
```

Ein Readiness-Gate in der Suite wartet zu Beginn auf Backend, Prometheus, Tempo,
Loki und Grafana; ist der Stack nicht bereit, bricht die Suite mit klarer Meldung ab.

## Aufruf

```bash
cd tests/observability
./run.sh                     # alle Tests inkl. Pipeline (E1, telemetrygen)
./run.sh -m "not pipeline"   # ohne den telemetrygen-Pipeline-Test
./run.sh -m smoke            # nur schnelle Smoke-Checks
```

`run.sh` setzt Env-Defaults, installiert bei Bedarf `pytest`/`requests`
(`requirements.txt`) und liefert einen Exit-Code (0 = alles gruen).

## Env-Variablen (mit Defaults)

| Variable | Default | Zweck |
|----------|---------|-------|
| `BACKEND_URL` | `http://localhost:8081` | Bestell-Backend + `/actuator/prometheus` |
| `PROM_URL` | `http://localhost:9090` | Prometheus-API |
| `TEMPO_URL` | `http://localhost:3200` | Tempo-API |
| `LOKI_URL` | `http://localhost:3100` | Loki-API |
| `GRAFANA_URL` | `http://localhost:3000` | Grafana-API |
| `GRAFANA_USER` / `GRAFANA_PASS` | `admin` / `admin` | Grafana BasicAuth |
| `STRICT_NODE_EXPORTER` | `false` | node-exporter-Target strikt als `up` fordern |
| `RUN_TELEMETRYGEN` | `true` | E1-Pipeline-Test aktiv (sonst geskippt) |

## Marker

- `@pytest.mark.smoke` – schnelle Praesenz-Checks: F2, A1, A2, A6, A8, C1, C4, C5, G3
- `@pytest.mark.e2e` – End-to-End ueber Traffic: B1, B2, C2, C3, D1
- `@pytest.mark.pipeline` – separater E1-Test via `telemetrygen` (Docker noetig)

## Testfaelle

| Fall | Datei | Prueft |
|------|-------|--------|
| F2 | `test_infra.py` | Grafana-Health + Datasources (Prometheus/Loki/Tempo) |
| A8 | `test_infra.py` | alle Prometheus-Targets `up` (node-exporter tolerant) |
| A1/A2/A4/A6 | `test_metrics.py` | Actuator-Format, Business- & JVM-Serien, fehlgeschlagene Bestellung zaehlt nicht |
| B1/B2/B3/B4/B5 | `test_traces.py` | Trace-Praesenz, Span-Namen, Trace-Tiefe (HTTP+DB), Span-/Resource-Attribute, plausible Dauer |
| C1–C5 | `test_logs.py` | Loki-Label, Log-Inhalt, trace/span-IDs, Resource-Labels, Severity |
| D1 | `test_correlation.py` | Trace↔Log-Korrelation ueber eindeutigen Kunden-Marker |
| E1/E2/E3 | `test_pipeline.py` | `telemetrygen` → Collector → Tempo (Traces) / Loki (Logs) / Prometheus (Metrics) |
| A7 + PromQL | `test_promql.py` | rechnende PromQL-Queries: Scrape-Delta, `rate()`, `histogram_quantile` p95, `sum by(status)`, Ø-Bestellwert |
| G3 | `test_freshness.py` | Frische der juengsten Telemetrie (Prom/Tempo/Loki) |

## Design

- **Asynchrone Telemetrie** wird ueber `until()` abgewartet (kein festes `sleep`).
- **Keine absoluten Zaehlerwerte** – es werden Praesenz/Marker genutzt; D1 arbeitet mit
  einem eindeutigen `customer=obs-ci-<run_id>` je Session.
- **Tempo-Search** verwendet ein explizites Zeitfenster (`start`/`end`), damit auch
  frische Traces zuverlaessig gefunden werden.
- Der E1-Pipeline-Test **skippt** sauber, wenn `RUN_TELEMETRYGEN=false`, `docker`
  fehlt oder das Compose-Netz nicht gefunden wird (kein harter Fehler).

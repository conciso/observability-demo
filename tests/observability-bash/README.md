# Observability-Suite – curl + bash (ohne Test-Framework)

1:1-Portierung der pytest-Suite aus [`../observability/`](../observability/) auf
**reines curl + bash** – gleiche Endpoints, gleiche PromQL-/TraceQL-/LogQL-Queries,
gleiche Assertions. Kein Python/pytest. Nicht-interaktiv, Exit-Code-basiert
(CI-tauglich). Die Original-pytest-Suite bleibt unveraendert.

## Voraussetzungen

- **Pflicht-Werkzeuge:** `curl`, `jq` (Preflight bricht sonst mit klarer Meldung ab).
- Weitere Standard-Tools: `awk`, `grep`, `sed`, `od`, `base64`, `date` (in macOS + Linux vorhanden).
- **`docker`** nur fuer die telemetrygen-Pipeline-Checks E1–E3 (sonst sauberer Skip).
- Der komplette Stack **laeuft und ist healthy** (`monitoring/docker-compose.yml`).

## Aufruf

```bash
cd tests/observability-bash
./run.sh                               # alle Gruppen
./run.sh --only "metrics traces"       # nur ausgewaehlte Gruppen
OBS_GROUPS="logs promql" ./run.sh      # dito per Env-Variable
RUN_TELEMETRYGEN=false ./run.sh        # Pipeline-Checks (E1–E3) werden geskippt
```

> Hinweis: Die Env-Variable heisst **`OBS_GROUPS`**, nicht `GROUPS` – `GROUPS`
> ist in Bash eine reservierte Spezial-Variable (Gruppen-IDs des Users).

Exit-Code `0` = kein Pflicht-Check fehlgeschlagen (Skips zaehlen nicht als Fehler),
sonst `1`. Preflight-/Readiness-/Traffic-Fehler beenden mit `2`.

## Env-Variablen (mit Defaults)

| Variable | Default | Zweck |
|----------|---------|-------|
| `BACKEND_URL` | `http://localhost:8081` | Backend + `/actuator/prometheus` |
| `PROM_URL` | `http://localhost:9090` | Prometheus-API |
| `TEMPO_URL` | `http://localhost:3200` | Tempo-API |
| `LOKI_URL` | `http://localhost:3100` | Loki-API |
| `GRAFANA_URL` | `http://localhost:3000` | Grafana-API |
| `GRAFANA_USER` / `GRAFANA_PASS` | `admin` / `admin` | Grafana BasicAuth |
| `STRICT_NODE_EXPORTER` | `false` | node-exporter-Target strikt als `up` fordern |
| `RUN_TELEMETRYGEN` | `true` | Pipeline-Checks E1–E3 aktiv |
| `OBS_GROUPS` | *(alle)* | Auswahl der Check-Gruppen |

## Struktur

| Datei | Inhalt |
|-------|--------|
| `run.sh` | Orchestrator: Preflight, Readiness-Gate, Traffic, Gruppen, Summary, Exit-Code |
| `lib.sh` | Helfer: `pass/fail/skip`, `retry()` (Ersatz fuer `until()`), curl-Wrapper, `promql_*`, `loki_query_range`, `tempo_search`, Actuator-Text, `place_orders`, base64→hex |
| `checks_infra.sh` | A8, F2 |
| `checks_metrics.sh` | A1, A2, A6, A4 |
| `checks_promql.sh` | A7, rate, histogram_quantile p95, sum by(status), Ø-Bestellwert |
| `checks_traces.sh` | B1, B2, B5, B4 (+ B4-Business = Skip), B3 |
| `checks_logs.sh` | C1–C5 |
| `checks_correlation.sh` | D1 |
| `checks_freshness.sh` | G3 (Prometheus/Tempo/Loki) |
| `checks_pipeline.sh` | E1, E2, E3 (telemetrygen) |

## Portierungs-/Portabilitaets-Hinweise

- **`retry()`** ersetzt `until()`: wiederholt ein Kommando bis Exit 0 oder Timeout
  (Metriken/PromQL ~60s wegen 15s-Scrape, B3 90s wegen WAL-Flush, E2/E3 60s).
- **Tempo-Search** immer mit explizitem `start`/`end`-Fenster (`now-900 … now+5`),
  sonst liefert Tempo aeltere/gecachte Treffer.
- **Loki `query_range`** mit Nanosekunden-Fenster (`now-15m … now+1m`); Nanosekunden
  werden portabel als `sekunden*1000000000` gebildet (kein `date +%N` noetig).
- **A4** deterministisch ueber den Actuator-Text (`awk`-Summe der
  `orders_created_total`-Serien), Vor/Nach-Vergleich, keine gueltige Bestellung.
- **D1**: `trace_id` aus dem Loki-Stream-Label; Tempo-`traceId` aus `/api/traces`
  ist **base64** → via `base64 -d | od -An -tx1` nach Hex normalisiert und verglichen.
- **B4-Business** (`order.item_count`) bleibt bewusst ein **Skip** (Attribut existiert
  nicht; der OTel-Agent exportiert die Micrometer-Observation nur als Metrik).
- **E3-Metrik** erscheint in Prometheus als `gen_total{exported_job="telemetrygen-metrics-<RUN_ID>"}`.
- Farben nur am TTY; in CI (Pipe/Redirect) automatisch aus.

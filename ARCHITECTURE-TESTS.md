# Architektur & Test-Ansatzpunkte

Grafische Übersicht der OpenTelemetry-Demo mit den Stellen, an denen die einzelnen
Tests ansetzen. Welche Prüfungen davon tatsächlich umgesetzt sind, steht im
[`TELEMETRY-BLACKBOX-TESTKATALOG.md`](./TELEMETRY-BLACKBOX-TESTKATALOG.md).
Die zugrunde liegenden Testpläne und die ausführliche Entwurfsdokumentation werden
projektintern gepflegt und sind nicht Teil dieses Repositories.

## Architektur mit Test-Ansatzpunkten

```
                    DOCKER-HOST · docker compose (name: monitoring)
 ══════════════════════════════════════════════════════════════════════════════

  ┌───────────────┐
  │  Angular UI   │   HTTP  /api  (nginx-Proxy → backend:8081)
  │  nginx :8082  │─────────────────────────┐
  └───────────────┘                         │        ◄╌╌ Frontend-Tests: OFFEN
   ╌╌ (Unit/E2E offen)                       ▼
                                 ┌────────────────────────────────┐
   Suite erzeugt Last ─────────►│        Spring Backend :8081     │
   (traffic-Fixture)            │                                 │
                                │  Instrumentierung / Bestell-    │◄── Typ1  Metrik-Unit
                                │  logik  (in-JVM, VOR Export)    │◄── Typ2  Observation
                                │                                 │◄── Typ3  Trace-SDK
                                │  /actuator/prometheus  ─────────┼── A1 A2 A6  (Exposition)
                                │                                 │   A4 (Fehler zählt nicht)
                                └───┬────────────────────┬────────┘   Typ4 Typ5 (in-code)
                          OTLP     │                     ▲              G1 Fehler-Telem.: OFFEN
                       traces+logs │            scrape   │ A7 (Δ) · A5 (rate/sum_by) · A3
                                   ▼                     │
   ┌────────────┐   OTLP   ┌──────────────────┐         │
   │telemetrygen│─────────►│  OTel Collector  │         │
   │ synthetic  │ E1/E2/E3 │ :4317 :4318 :8889│         │
   └────────────┘          └───┬────┬──────┬──┘         │
                               │    │      │ metrics    │
                        traces │logs│      │ (:8889)    │
                               ▼    ▼      ▼            │
                          ┌───────┐┌──────┐┌────────────┴─────┐
      node-exporter :9100─┤ Tempo ││ Loki ││   Prometheus     │
      cadvisor      :8080─┤ :3200 ││:3100 ││    :9090         │
            scrape  A8 ───┤       ││      ││                  │
                          └───┬───┘└──┬───┘└─────────┬────────┘
        B1 B2 B3 B4 B5 ───────┘  C1..C5│   E3         │  PromQL: rate,
        E1 (traces)         E2 (logs)──┘              │  histogram_quantile,
                               │                      │  sum_by, avg
                    D1  Korrelation                   │  G3 (freshness)
                    Loki.trace_id ◄──────────────────►│  G2 Kardinalität: OFFEN
                       ↕  Tempo.traceID               │
                               │                      │
                               └──────► Grafana :3000 ◄──── F2  Health/Datasources
                                        :3000              F3  Panel-Query: OFFEN
                                        (Explore/Dashboards)

  alloy ─────► Loki            (Container-Logs)
  ────────────────────────────────────────────────────────────────────────────
  Statische Configs: prometheus.yml · tempo.yaml · loki-config.yaml ·
  otel-collector-config.yaml · alloy-config.alloy · grafana/provisioning
                                                         └── F1  validate-configs.sh
```

## Legende — welcher Test setzt wo an

| Ansatzpunkt | Tests | Art / Status |
|-------------|-------|--------------|
| **Backend-Instrumentierung** (in-JVM, vor Export) | **Typ1** Metrik-Unit · **Typ2** Observation · **Typ3** Trace-SDK | in-code ✅ |
| **Backend `/actuator/prometheus`** (Exposition) | **A1, A2, A6** · **A4** · in-code **Typ4, Typ5** | black-box + in-code ✅ · **G1** offen |
| **Scrape-Pfad Backend→Prometheus** | **A7** (Δ), **A5** (rate/sum_by), **A3** (≈A7) | PromQL ✅ (A3/A5 äquivalent) |
| **Prometheus** (`:9090`) | rate · histogram_quantile · sum_by · avg · **G3** · **A8** (Targets up) | PromQL ✅ · **G2** offen |
| **Tempo** (`:3200`, TraceQL) | **B1, B2, B3, B4, B5** · **E1** · **G3** | ✅ (B4-Business-Attr. = Skip) |
| **Loki** (`:3100`, LogQL) | **C1–C5** · **E2** · **G3** | ✅ |
| **Korrelation Loki↔Tempo** | **D1** | ✅ |
| **Collector-Pipeline** (isoliert) | **E1** traces · **E2** logs · **E3** metrics (via telemetrygen) | ✅ |
| **Grafana** (`:3000`) | **F2** Health/Datasources | ✅ · **F3** Panel-Query offen |
| **Statische Configs** | **F1** (`validate-configs.sh`) | ✅ |
| **Frontend** (`:8082`) | – | ❌ noch keine Tests |

## Test-Ebenen

- **In-code (Backend, in-JVM):** Typ 1–5 unter `backend/src/test/...` – laufen ohne Stack
  im Gradle-Build. Typ 7 = `monitoring/validate-configs.sh` (statische Config-Validierung).
- **Black-box (gegen laufenden Stack):** `tests/observability/` (pytest) – A/B/C/D/E/F/G,
  fahren PromQL/TraceQL/LogQL gegen Prometheus/Tempo/Loki + Grafana-/Backend-APIs.
- **Pipeline isoliert:** E1/E2/E3 injizieren via `telemetrygen` synthetische Signale in den
  Collector und weisen sie in Tempo/Loki/Prometheus nach (ohne die App).

## Status-Kurzfassung

- ✅ **Implementiert:** 23 Plan-Checks (A/B/C/D/E/F/G) + 2 äquivalent (A3, A5) + in-code Typ 1–5 + F1
- 🟡 **Skip (dokumentiert):** B4-Business-Attribut `order.item_count` – der OTel-Java-Agent
  exportiert die Micrometer-Observation nur als Metrik, nicht als Span
- ❌ **Offen:** F3 (Dashboard-Panel-Query), G1 (Fehler-Telemetrie), G2 (Kardinalitäts-Wächter)
  sowie **Frontend-Tests** (Unit + E2E)
```

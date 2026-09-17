# Testkatalog: Telemetrie als Black-Box – Umsetzungsstand

> Kopie des Testkatalogs aus dem projektinternen Telemetrie-Black-Box-Testplan (§3),
> ergänzt um den **tatsächlichen Umsetzungsstand**. Der Testplan bleibt die fachliche Quelle
> und ist nicht Teil dieses Repositories; diese Datei beantwortet nur die Frage
> „was ist davon gebaut?".
>
> Stand: 2026-09-16 · geprüft gegen drei Ebenen:
> **BB** = Black-Box-Suiten `tests/observability/` (pytest) und `tests/observability-bash/`
> (curl+bash) – beide decken dieselben IDs ab ·
> **JUnit** = Backend-Tests `backend/src/test/` (6 Klassen) ·
> **Config** = `monitoring/validate-configs.sh`

## Legende

| Marke | Bedeutung |
|-------|-----------|
| ✅ | realisiert – die Assertion des Plans wird geprüft |
| 🟡 | **teilweise realisiert** – nur abgeschwächt oder nur auf einer Ebene geprüft |
| ❌ | **nicht realisiert** – keine automatisierte Prüfung vorhanden |

Aufwand (aus dem Plan übernommen): 🟢 billig/schnell · 🟡 mittel · 🔴 aufwändig.

---

## A. Metriken-Kette

| ID | Prüfung | Assertion | Aufw. | Status | Realisiert als |
|----|---------|-----------|-------|--------|----------------|
| A1 | Exposition erreichbar & valide | `GET /actuator/prometheus` → 200, parsebar (Prometheus-Textformat) | 🟢 | ✅ | BB `test_a1_actuator_prometheus_parsebar` / `check_a1` · JUnit `ActuatorPrometheusMetricsTest` |
| A2 | **Exakte** Business-Namen vorhanden | `orders_created_total`, `order_value_euros_{count,sum,bucket}` existieren | 🟢 | ✅ | BB `test_a2_business_metrics_vorhanden` / `check_a2` · JUnit `OrderMetricsEndToEndTest` (prüft alle vier Namen inkl. `_bucket{`) |
| A3 | Semantik: erfolgreiche Bestellung zählt | Δ`orders_created_total` == Anzahl gesendeter gültiger Bestellungen; `order_value_euros_sum` steigt um Bestellwert | 🟡 | ✅ | **JUnit `OrderMetricsEndToEndTest.businessMetricsReflectTrafficExactly`** – exakter Delta-Vergleich **und** `order_value_euros_sum`. BB deckt nur den Zählerteil ab (A7 prüft `>= M` statt `== M`, ohne `_sum`) |
| A4 | Semantik: fehlgeschlagene Bestellung zählt **nicht** | Bestellung mit unbekanntem Produkt (404) → `orders_created_total` unverändert | 🟡 | ✅ | BB `test_a4_…` / `check_a4` · JUnit `OrderServiceTest.doesNotCountFailedOrder` + `OrderMetricsEndToEndTest` (ungültige Bestellung im selben Lauf) |
| A5 | HTTP-Metriken + Labels | `http_server_requests_seconds_count{uri="/api/orders",status="201"}` **steigt** | 🟢 | 🟡 | BB `test_sum_by_status` / `check_sum_by_status` prüft die Labels `uri`+`status=201` mit Wert ≥ 1 – **aber keinen Anstieg (kein Delta)**. JUnit prüft nur, dass `http_server_requests_seconds` überhaupt auftaucht, ohne Labels |
| A6 | Standard-JVM/Prozess-Metriken | `jvm_memory_used_bytes`, `jvm_threads_live_threads`, `process_cpu_usage` vorhanden | 🟢 | ✅ | BB `test_a6_jvm_metrics_vorhanden` / `check_a6` |
| A7 | **Scrape-Pfad** (Endpoint→Prometheus) | `orders_created_total` via Prometheus `:9090` liefert denselben Anstieg | 🟡 | ✅ | BB `test_a7_scrape_pfad_delta` / `check_a7` |
| A8 | Alle Scrape-Ziele `up` | `/api/v1/targets` → `health=up` (node-exporter je nach Host, s. Plan §8) | 🟢 | ✅ | BB `test_a8_prometheus_targets_up` / `check_a8` |

## B. Traces-Kette

| ID | Prüfung | Assertion | Aufw. | Status | Realisiert als |
|----|---------|-----------|-------|--------|----------------|
| B1 | Traces des Service vorhanden | Tempo-Search `{ resource.service.name="food-order-backend" }` → ≥1 Trace | 🟡 | ✅ | BB `test_b1_traces_vorhanden` / `check_b1` |
| B2 | Erwartete Span-Namen | Traces für `POST /api/orders` **und** `GET /api/products` existieren | 🟡 | ✅ | BB `test_b2_span_namen_vorhanden` / `check_b2` |
| B3 | **Trace-Tiefe** (Auto-Instrumentierung greift) | Order-Trace hat >1 Span (HTTP-Server + JPA/DB-Span) | 🟡 | ✅ | BB `test_b3_trace_tiefe_http_und_db` / `check_b3` |
| B4 | Ressourcen-/Span-Attribute (Semantic Conventions) | Trace/Span trägt `service.namespace`, `deployment.environment`, `http.*` | 🟡 | ✅ | BB `test_b4_span_und_resource_attribute` / `check_b4` · JUnit `OrderTracingTest` (Span-Attribute + Parent-Child via OTel-SDK) |
| B5 | Latenz-Plausibilität | `durationMs > 0` und < sinnvolle Obergrenze | 🟢 | ✅ | BB `test_b5_trace_dauer_plausibel` / `check_b5` |

> **Bewusst übersprungen, nicht vergessen:** `test_b4_business_attribute_order_item_count` /
> `check_b4_business` steht dauerhaft auf SKIPPED/⚠. `order.item_count` ist in der Praxis **kein**
> Span-Attribut – der OTel-Java-Agent exportiert die Micrometer-Observation `orders.create` nur
> als Metrik. Dass die Anwendung den Span mit den Attributen **erzeugt**, beweist dagegen
> `OrderTracingTest.producesOrdersCreateSpan` per OTel-SDK (`order.item_count=2`,
> `order.value_cents=2248`, Parent-Child korrekt). Die Lücke liegt also im Agent-Export,
> nicht im Code – und beide Ebenen zusammen zeigen das.

## C. Logs-Kette

| ID | Prüfung | Assertion | Aufw. | Status | Realisiert als |
|----|---------|-----------|-------|--------|----------------|
| C1 | Logs des Service vorhanden | Loki-Label `service_name` enthält `food-order-backend` | 🟢 | ✅ | BB `test_c1_service_name_label` / `check_c1` |
| C2 | Fachliche Log-Zeile | nach Bestellung: Log „Created order id=… cents" vorhanden | 🟡 | ✅ | BB `test_c2_created_order_logzeile` / `check_c2` |
| C3 | **trace_id/span_id am Log** | Log-Streams tragen nicht-leere `trace_id`/`span_id` (Structured Metadata) | 🟡 | ✅ | BB `test_c3_trace_und_span_id_labels` / `check_c3` |
| C4 | Ressourcen-Attribute als Labels | `service_namespace`, `deployment_environment`, `service_version` vorhanden | 🟢 | ✅ | BB `test_c4_resource_labels` / `check_c4` |
| C5 | Level-Mapping | `severity_text`/`detected_level` = INFO/WARN korrekt | 🟢 | ✅ | BB `test_c5_severity_vorhanden` / `check_c5` |

## D. Korrelation (Kronjuwel)

| ID | Prüfung | Assertion | Aufw. | Status | Realisiert als |
|----|---------|-----------|-------|--------|----------------|
| D1 | **Ein Request über alle Signale** | Bestellung mit eindeutigem `customerName="ci-<runId>"` → passenden Loki-Log finden → dessen `trace_id` auslesen → in Tempo existiert ein `POST /api/orders`-Trace mit **genau dieser** traceID | 🔴 | ✅ | BB `test_d1_trace_log_korrelation` / `check_d1` (dort 90 s Verify-Timeout nötig, sonst flaky) |

## E. Pipeline isoliert (ohne App) – `telemetrygen`

| ID | Prüfung | Assertion | Aufw. | Status | Realisiert als |
|----|---------|-----------|-------|--------|----------------|
| E1 | Collector→Tempo | `telemetrygen traces` an `:4317` → Trace mit dessen Service-Namen in Tempo | 🟡 | ✅ | BB `test_e1_telemetrygen_traces` / `check_e1` |
| E2 | Collector→Loki | `telemetrygen logs` → in Loki auffindbar | 🟡 | ✅ | BB `test_e2_telemetrygen_logs` / `check_e2` |
| E3 | Collector→Prometheus | `telemetrygen metrics` → am Collector-`:8889` bzw. in Prometheus sichtbar | 🟡 | ✅ | BB `test_e3_telemetrygen_metrics` / `check_e3` (erscheint als `gen_total{exported_job=…}`) |

## F. Infrastruktur & Config

| ID | Prüfung | Assertion | Aufw. | Status | Realisiert als |
|----|---------|-----------|-------|--------|----------------|
| F1 | Statische Config-Validierung | `docker compose config -q`, `promtool check config`, `otelcol validate`, Dashboard-JSON-Lint | 🟢 | ✅ | **Config** `monitoring/validate-configs.sh` – 9 Checks, Exit-Code-basiert (außerhalb der BB-Suiten) |
| F2 | Grafana-Health + Datasource-Health | `/api/health` 200; Prometheus/Loki/Tempo-Datasource-Health = OK | 🟢 | ✅ | BB `test_f2_grafana_health_and_datasources` / `check_f2` |
| F3 | Dashboards provisioniert & liefern Daten | `/api/search?type=dash-db` enthält die 3 Dashboards; ein Panel-Query via `/api/ds/query` liefert Werte | 🟡 | ❌ | **nicht realisiert** |

## G. Robustheit / Negativ (optional, Ausbaustufe)

| ID | Prüfung | Assertion | Aufw. | Status | Realisiert als |
|----|---------|-----------|-------|--------|----------------|
| G1 | Fehler erzeugen Fehler-Telemetrie | 4xx/5xx triggern → `http_server_requests…{status="4xx/5xx"}` + Span-Status error | 🟡 | 🟡 | JUnit `OrderObservationTest.marksObservationErroredOnUnknownProduct` prüft, dass die Observation als **fehlerhaft markiert** wird (`ProductNotFoundException`). **Offen:** die Metrik-Seite (`http_server_requests…{status="404"}`) und der Span-Status im tatsächlich exportierten Trace |
| G2 | Kardinalitäts-Wächter | Serienanzahl je Metrik bleibt unter Schwelle (kein Label-Explosion) | 🟡 | ❌ | **nicht realisiert** |
| G3 | **Freshness** | jüngste Metrik/Trace/Log-Zeitstempel liegt innerhalb der letzten X min (nichts „steht") | 🟢 | ✅ | BB `test_g3_freshness_{prometheus,tempo,loki}` / `check_g3_{prom,tempo,loki}` |

---

## Zusammenfassung

| Status | Anzahl | IDs |
|--------|--------|-----|
| ✅ realisiert | 24 | A1, A2, A3, A4, A6, A7, A8, B1–B5, C1–C5, D1, E1–E3, F1, F2, G3 |
| 🟡 teilweise | 2 | **A5, G1** |
| ❌ nicht realisiert | 2 | **F3, G2** |

**28 Prüfungen im Katalog.** Ohne die Backend-JUnit-Tests wären A3 nur teilweise und G1 gar
nicht abgedeckt – erst beide Ebenen zusammen ergeben das Bild.

### Was zu den offenen Punkten konkret fehlt

- **A5 🟡 – kein Delta.** Geprüft wird, dass `http_server_requests_seconds_count` mit
  `uri="/api/orders"` und `status="201"` existiert und ≥ 1 ist. Der Plan verlangt, dass der Wert
  **steigt**. Eine eingefrorene HTTP-Metrik (Wert bleibt konstant) fiele heute nicht auf.
  Aufwand gering: Baseline lesen, Traffic, Delta prüfen – analog A7.
- **G1 🟡 – nur die halbe Kette.** Dass die Observation bei unbekanntem Produkt als fehlerhaft
  markiert wird, ist auf Unit-Ebene bewiesen. Ob daraus im laufenden Stack ein
  `status="404"` in den HTTP-Metriken und ein Span mit Fehlerstatus wird, prüft nichts.
- **F3 ❌ – Dashboards ungeprüft.** F2 zeigt nur, dass Grafana und seine Datasources gesund sind.
  Ob die drei provisionierten Dashboards existieren und ihre Panels Werte liefern, fällt erst beim
  Hinsehen auf. Ein kaputtes Panel-Query bleibt unbemerkt.
- **G2 ❌ – keine Kardinalitäts-Grenze.** Konkreter Anlass: `order_value_euros` erzeugt allein
  durch `.publishPercentileHistogram()` **276 Bucket-Serien**.

### Einschränkung, die für alle Black-Box-Tests gilt

Die BB-Suiten erzeugen **immer frischen Traffic** und prüfen unmittelbar danach. Defekte, die erst
*später* auftreten – etwa Traces, die nach Stunden nicht mehr auffindbar sind – findet dieser
Ansatz prinzipbedingt nicht. Genau dieser Fall trat am 16.09.2026 auf (hängender
Tempo-Tenant-Index: ältere Traces lautlos unauffindbar) und blieb bei 28 grünen Prüfungen
unentdeckt. Ein Test, der einen Trace **nach** dem live-store-Fenster erneut abruft, wäre die
passende Ergänzung – im Katalog gibt es dafür bisher keine ID.

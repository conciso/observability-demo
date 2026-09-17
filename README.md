# OpenTelemetry-Demo – Lebensmittel-Bestellungen

Eine lauffähige Observability-Demo: Eine Bestell-Anwendung für Lebensmittel
(**Spring-Boot-Backend** + **Angular-Frontend**) wird end-to-end mit
**OpenTelemetry** überwacht – **Metriken**, **Logs** und **Traces**, inklusive
Trace↔Log-Korrelation. Der komplette Stack (App **und** Observability) läuft in
**einem** `docker compose` auf **einem** Docker-Host – es wird **keine separate VM**
benötigt.

> Architektur im Überblick, mit den Ansatzpunkten der Tests:
> siehe [`ARCHITECTURE-TESTS.md`](./ARCHITECTURE-TESTS.md).
> Die ausführlichen Entwurfsentscheidungen werden projektintern gepflegt und sind
> nicht Teil dieses Repositories.

---

## Architektur auf einen Blick

```
                Docker-Host (ein docker-compose)
  Angular ──HTTP──►  Spring-Boot ──OTLP──►  OTel-Collector ──►  Tempo   (Traces)
 (nginx, :8082)      Backend (:8081)                        ├──►  Loki    (Logs)
                          │                                 └──►  Prometheus (Metriken)
                          └─ /actuator/prometheus ◄─scrape──── Prometheus
   node-exporter (VM-Host-Metriken) + cAdvisor (Container) ──scrape──► Prometheus
                                                Grafana (:3000) ◄── Prometheus/Loki/Tempo
```

- **Traces:** Backend (OTel-Java-Agent) → Collector → **Tempo**
- **Logs:** Backend (OTel-Java-Agent) → Collector → **Loki**; Container-Logs via **Alloy**
- **Metriken:** Backend `/actuator/prometheus` + Host (**node-exporter**) + Container (**cAdvisor**) → **Prometheus**
- **Visualisierung:** **Grafana** mit vorprovisionierten Datasources & Dashboards

---

## Voraussetzungen

- **Docker** + **Docker Compose v2** (`docker compose …`)
- Freie Ports: `3000, 3100, 3200, 4317, 4318, 8080, 8081, 8082, 9090, 9100`
- Kein lokales JDK/Node nötig – alles wird in Multi-Stage-Docker-Builds gebaut.

---

## Schnellstart

```bash
# im Projektwurzel (dort liegt jetzt die docker-compose.yml)
docker compose up -d --build
```

Der erste Start baut die Images (Backend via Gradle/Java 25, Frontend via Node 24/nginx)
und lädt die Observability-Images – das dauert einige Minuten. Danach:

```bash
docker compose ps          # Status aller Container
docker compose logs -f backend   # Backend-Logs verfolgen
```

**Stoppen / Aufräumen:**

```bash
docker compose down        # Container stoppen (Daten in Volumes bleiben)
docker compose down -v     # zusätzlich alle Volumes löschen (Prometheus/Grafana/Loki/Tempo)
```

---

## Zugänge

| Dienst | URL | Zugangsdaten |
|--------|-----|--------------|
| **Frontend (Bestell-UI)** | http://localhost:8082 | – |
| **Grafana** | http://localhost:3000 | `admin` / `admin` |
| **Prometheus** | http://localhost:9090 | – |
| **Tempo (API)** | http://localhost:3200 | – |
| **Loki (API)** | http://localhost:3100 | – |
| **Backend-API** | http://localhost:8081 | – |

**Backend-Endpunkte:**

| Methode | Pfad | Zweck |
|---------|------|-------|
| `GET` | `/api/products` | Produktkatalog |
| `GET` | `/api/products/{id}` | Einzelnes Produkt |
| `POST` | `/api/orders` | Bestellung anlegen |
| `GET` | `/api/orders` / `/api/orders/{id}` | Bestellungen abrufen |
| `GET` | `/actuator/health` | Health (liveness/readiness) |
| `GET` | `/actuator/prometheus` | Prometheus-Metriken |

---

## Demo durchspielen

1. **Frontend öffnen:** http://localhost:8082 – Produkte in den Warenkorb legen, mit Namen bestellen.
   *(Alternativ per API:)*
   ```bash
   curl -X POST http://localhost:8081/api/orders \
     -H 'Content-Type: application/json' \
     -d '{"customerName":"Ada Lovelace","items":[{"productId":1,"quantity":2},{"productId":4,"quantity":3}]}'
   ```
2. **In Grafana ansehen** (http://localhost:3000):
   - **Dashboard „Spring Backend (food-order)"** – Bestellungen gesamt, Bestellwert, HTTP-Raten/Latenz, JVM.
   - **Dashboard „Traces & Logs (food-order)"** – letzte Traces + korrelierte Bestell-Logs.
   - **Dashboard „VM-Host (Node Exporter)"** – CPU/RAM/Netz/Disk des Hosts.
3. **Trace↔Log-Korrelation:** In **Explore → Tempo** einen Trace öffnen und im Span
   **„Logs for this span"** wählen → Grafana springt zur korrelierten Loki-Log-Zeile
   (Verknüpfung über `trace_id`).

---

## Dashboards & Datasources

Grafana wird beim Start automatisch provisioniert:

- **Datasources:** Prometheus (Default), Loki, Tempo (inkl. Trace→Log-Verknüpfung)
- **Dashboards** (unter `monitoring/grafana/provisioning/dashboards/`):
  `spring-backend.json`, `traces-logs.json`, `vm-host.json`

---

## Konfiguration validieren

Alle Observability-Configs lassen sich **statisch** (ohne den Stack zu starten)
prüfen – lokal und CI-tauglich (nicht-interaktiv, Exit-Code-basiert):

```bash
cd monitoring
./validate-configs.sh
```

Geprüft werden u. a. `docker compose config`, Prometheus (`promtool`),
OTel-Collector (`validate`), Loki/Tempo/Alloy (best-effort) sowie YAML-/JSON-Lint
aller Configs und Dashboards. Exit-Code `0` = alle Pflicht-Checks grün, sonst `1`.
Die Tool-Checks nutzen dieselben Docker-Images wie der Stack (Docker erforderlich).

---

## Ports

| Port | Dienst | Port | Dienst |
|------|--------|------|--------|
| 3000 | Grafana | 8081 | Backend |
| 9090 | Prometheus | 8082 | Frontend (nginx) |
| 3100 | Loki | 9100 | node-exporter |
| 3200 | Tempo | 8080 | cAdvisor |
| 4317/4318 | OTel-Collector (OTLP gRPC/HTTP) | | |

---

## Hinweise zum Host (Linux vs. Docker Desktop)

Der Schnellstart oben funktioniert auf **macOS/Windows (Docker Desktop)** und **Linux**.

- **Host-Metriken** (`node-exporter`, `cAdvisor`) sind nur auf einem **Linux-Docker-Host**
  aussagekräftig für den echten Host. Auf **Docker Desktop** messen sie die interne
  Docker-Desktop-Linux-VM (die Demo läuft dennoch vollständig).
- **`docker-compose.override.yml`** passt `node-exporter` für **Docker Desktop** an
  (entfernt die Mount-Propagation `rslave`, die auf Docker Desktop nicht unterstützt wird).
  Docker Compose merged diese Datei automatisch.
- **Auf einem echten Linux-Host** empfiehlt sich der Betrieb **ohne** die Override-Datei,
  damit die `rslave`-Propagation aus `docker-compose.yml` greift (erfasst auch dynamisch
  eingehängte Dateisysteme, z. B. für das Panel „Root-Filesystem-Belegung"):
  ```bash
  # im Projektwurzel
  docker compose -f docker-compose.yml up -d --build      # Override ignorieren
  # oder: docker-compose.override.yml löschen/umbenennen
  ```

---

## Technischer Stand

| Komponente | Version |
|------------|---------|
| Java | 25 (LTS) |
| Spring Boot | 4.1.x |
| Angular | 22 |
| Node (Build) | 24 (LTS) |
| Datenbank | H2 **in-memory** (Schema & Demo-Daten via **Flyway**, `V1`/`V2`) |

> **Datenbank-Hinweis:** H2 läuft in-memory und ist **nicht persistent** – bei jedem
> Backend-Neustart baut Flyway das Schema neu auf und lädt die Demo-Produkte (`V2`).

---

## Projektstruktur

```
.
├── README.md                     # dieses Dokument
├── ARCHITECTURE-TESTS.md         # Architektur-Diagramm & Test-Ansatzpunkte
├── TELEMETRY-BLACKBOX-TESTKATALOG.md  # Testkatalog mit Umsetzungsstand
├── docker-compose.yml            # alle Services (Einstiegspunkt)
├── docker-compose.override.yml   # Docker-Desktop-Anpassung (node-exporter)
├── monitoring/                   # Observability-Konfiguration
│   ├── prometheus.yml
│   ├── loki-config.yaml
│   ├── tempo.yaml
│   ├── otel-collector-config.yaml
│   ├── alloy-config.alloy
│   ├── validate-configs.sh
│   └── grafana/provisioning/     # Datasources + Dashboards
├── backend/                      # Spring-Boot-Backend (Java 25, JPA, H2, Flyway, OTel-Agent)
├── frontend/                     # Angular-22-Frontend (nginx, /api-Proxy)
└── tests/observability/          # Black-box-Telemetrie-Tests (pytest)
```

#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Entrypoint fuer die Observability-Black-Box-Suite (Quick-First-Suite).
# Nicht-interaktiv, Exit-Code-basiert. Vorbedingung: der Stack laeuft & ist
# healthy (siehe README). Traffic wird von der Suite selbst erzeugt.
#
# Aufruf:
#   ./run.sh                 # alle Tests inkl. Pipeline (E1)
#   ./run.sh -m "not pipeline"   # ohne telemetrygen-Pipeline
#   RUN_TELEMETRYGEN=false ./run.sh   # Pipeline-Test wird geskippt
# ---------------------------------------------------------------------------
set -uo pipefail
cd "$(dirname "$0")" || exit 2

# --- Env-Defaults (nur setzen, falls nicht vorgegeben) ----------------------
export BACKEND_URL="${BACKEND_URL:-http://localhost:8081}"
export PROM_URL="${PROM_URL:-http://localhost:9090}"
export TEMPO_URL="${TEMPO_URL:-http://localhost:3200}"
export LOKI_URL="${LOKI_URL:-http://localhost:3100}"
export GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
export GRAFANA_USER="${GRAFANA_USER:-admin}"
export GRAFANA_PASS="${GRAFANA_PASS:-admin}"
export STRICT_NODE_EXPORTER="${STRICT_NODE_EXPORTER:-false}"
export RUN_TELEMETRYGEN="${RUN_TELEMETRYGEN:-true}"

# --- Python-Interpreter waehlen ---------------------------------------------
PY="${PYTHON:-python3}"
if ! command -v "$PY" >/dev/null 2>&1; then
  echo "FEHLER: python3 nicht gefunden." >&2
  exit 2
fi

# --- Abhaengigkeiten sicherstellen (nur falls noetig) -----------------------
if ! "$PY" -c "import pytest, requests" >/dev/null 2>&1; then
  echo "Installiere Test-Abhaengigkeiten (pytest, requests) ..."
  "$PY" -m pip install --quiet --disable-pip-version-check -r requirements.txt || {
    echo "FEHLER: pip install fehlgeschlagen." >&2; exit 2; }
fi

# --- pytest ausfuehren (weitere Args werden durchgereicht) ------------------
"$PY" -m pytest -v "$@"
exit $?

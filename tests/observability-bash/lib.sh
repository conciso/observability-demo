# shellcheck shell=bash
# ---------------------------------------------------------------------------
# lib.sh – gemeinsame Helfer der Bash/curl-Observability-Suite.
# Wird von run.sh via `source` eingebunden. Kein eigenes set -e hier.
# Portabel fuer macOS (BSD) und Linux (GNU): keine %N-Nanosekunden, base64 -d,
# Hex via od.
# ---------------------------------------------------------------------------

# --- Env-Variablen mit Defaults ---------------------------------------------
: "${BACKEND_URL:=http://localhost:8081}"
: "${PROM_URL:=http://localhost:9090}"
: "${TEMPO_URL:=http://localhost:3200}"
: "${LOKI_URL:=http://localhost:3100}"
: "${GRAFANA_URL:=http://localhost:3000}"
: "${GRAFANA_USER:=admin}"
: "${GRAFANA_PASS:=admin}"
: "${STRICT_NODE_EXPORTER:=false}"
: "${RUN_TELEMETRYGEN:=true}"

BACKEND_URL="${BACKEND_URL%/}"
PROM_URL="${PROM_URL%/}"
TEMPO_URL="${TEMPO_URL%/}"
LOKI_URL="${LOKI_URL%/}"
GRAFANA_URL="${GRAFANA_URL%/}"

HTTP_TIMEOUT=10
SVC="food-order-backend"
TELEMETRYGEN_IMAGE="ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen"

# --- Ergebnis-Zaehler (analog validate-configs.sh) --------------------------
PASS_N=0
FAIL_N=0
SKIP_N=0
FAILED_LIST=""

# Farben nur am TTY.
if [ -t 1 ]; then
  C_GREEN="\033[0;32m"; C_RED="\033[0;31m"; C_YELLOW="\033[0;33m"; C_BOLD="\033[1m"; C_OFF="\033[0m"
else
  C_GREEN=""; C_RED=""; C_YELLOW=""; C_BOLD=""; C_OFF=""
fi

pass() { PASS_N=$((PASS_N+1)); printf "${C_GREEN}\xE2\x9C\x93${C_OFF} %s\n" "$1"; }
fail() {
  FAIL_N=$((FAIL_N+1)); FAILED_LIST="${FAILED_LIST}\n  - $1"
  printf "${C_RED}\xE2\x9C\x97${C_OFF} %s\n" "$1"
  [ -n "${2:-}" ] && printf "    | %s\n" "$2"
  return 0
}
skip() { SKIP_N=$((SKIP_N+1)); printf "${C_YELLOW}\xE2\x9A\xA0${C_OFF} %s ${C_YELLOW}(uebersprungen)${C_OFF}\n" "$1"; }

# --- retry(): Ersatz fuer until() -------------------------------------------
# retry <timeout_s> <interval_s> <cmd> [args...]
# Ruft cmd wiederholt auf, bis Exit 0 oder Timeout. Rueckgabe: 0/1.
retry() {
  local timeout="$1" interval="$2"; shift 2
  local deadline=$(( $(date +%s) + timeout ))
  while :; do
    if "$@" >/dev/null 2>&1; then return 0; fi
    if [ "$(date +%s)" -ge "$deadline" ]; then return 1; fi
    sleep "$interval"
  done
}

# --- Float-Vergleiche (via awk) ---------------------------------------------
fgt() { awk "BEGIN{exit !($1 > $2)}"; }   # 0, wenn $1 > $2
fge() { awk "BEGIN{exit !($1 >= $2)}"; }  # 0, wenn $1 >= $2

# --- HTTP-Helfer -------------------------------------------------------------
http_code() { curl -s -o /dev/null -w '%{http_code}' --max-time "$HTTP_TIMEOUT" "$@"; }

# --- Prometheus --------------------------------------------------------------
promql_raw() { # <query> -> rohes JSON
  curl -sG --max-time "$HTTP_TIMEOUT" "$PROM_URL/api/v1/query" --data-urlencode "query=$1"
}

# Summe aller Vektor-Werte (NaN/Inf werden aussortiert; analog instant_sum).
promql_instant_sum() { # <query> -> float
  promql_raw "$1" | jq -r '
    [ .data.result[].value[1]
      | select(. != "NaN" and . != "+Inf" and . != "-Inf" and . != "Inf")
      | tonumber ] | add // 0'
}

# Anzahl der Vektor-Elemente.
promql_count() { # <query> -> int
  promql_raw "$1" | jq -r '.data.result | length'
}

# --- Loki --------------------------------------------------------------------
loki_query_range() { # <logql> [limit] -> rohes JSON (Fenster now-15m..now+1m, ns)
  local q="$1" limit="${2:-10}" now s e
  now=$(date +%s)
  s=$(( (now - 15*60) * 1000000000 ))
  e=$(( (now + 60) * 1000000000 ))
  curl -sG --max-time "$HTTP_TIMEOUT" "$LOKI_URL/loki/api/v1/query_range" \
    --data-urlencode "query=$q" \
    --data-urlencode "start=$s" \
    --data-urlencode "end=$e" \
    --data-urlencode "limit=$limit" \
    --data-urlencode "direction=backward"
}

# --- Tempo -------------------------------------------------------------------
tempo_search() { # <traceql> [limit] -> rohes JSON (explizites Fenster now-900..now+5)
  local q="$1" limit="${2:-5}" now
  now=$(date +%s)
  curl -sG --max-time "$HTTP_TIMEOUT" "$TEMPO_URL/api/search" \
    --data-urlencode "q=$q" \
    --data-urlencode "limit=$limit" \
    --data-urlencode "start=$(( now - 900 ))" \
    --data-urlencode "end=$(( now + 5 ))"
}
tempo_count() { tempo_search "$1" "${2:-5}" | jq -r '.traces // [] | length'; }

# --- Actuator-Text -----------------------------------------------------------
actuator_text() { curl -s --max-time "$HTTP_TIMEOUT" "$BACKEND_URL/actuator/prometheus"; }

# Summe aller orders_created_total-Serien aus dem Actuator-Text (fuer A4).
actuator_orders_total() {
  actuator_text | awk '
    $1 ~ /^orders_created_total(\{.*\})?$/ { s += $2 }
    END { printf "%s", s+0 }'
}

# --- Bestell-Helfer ----------------------------------------------------------
place_orders() { # <customer> <count>
  local c="$1" cnt="${2:-1}" i code
  for (( i=0; i<cnt; i++ )); do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time "$HTTP_TIMEOUT" \
      -X POST "$BACKEND_URL/api/orders" -H 'Content-Type: application/json' \
      -d "{\"customerName\":\"$c\",\"items\":[{\"productId\":1,\"quantity\":2}]}")
    [ "$code" = "201" ] || return 1
  done
  return 0
}

# --- Docker/telemetrygen-Netz ------------------------------------------------
find_monitoring_network() {
  local nets suffixed
  command -v docker >/dev/null 2>&1 || return 1
  nets=$(docker network ls --format '{{.Name}}' 2>/dev/null | grep monitoring || true)
  [ -n "$nets" ] || return 1
  suffixed=$(printf '%s\n' "$nets" | grep -E '_monitoring$' | head -1 || true)
  if [ -n "$suffixed" ]; then printf '%s' "$suffixed"; else printf '%s' "$(printf '%s\n' "$nets" | head -1)"; fi
}

# base64 (mit -d, Fallback -D) -> lowercase Hex.
b64_to_hex() {
  local data="$1" raw
  raw=$(printf '%s' "$data" | base64 -d 2>/dev/null || printf '%s' "$data" | base64 -D 2>/dev/null)
  printf '%s' "$raw" | od -An -tx1 | tr -d ' \n'
}

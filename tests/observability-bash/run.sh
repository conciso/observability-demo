#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Observability-Black-Box-Suite als reine curl+bash-Loesung (ohne pytest).
# Portiert 1:1 die Checks aus ../observability/ (pytest). Nicht-interaktiv,
# Exit-Code-basiert. Vorbedingung: der Stack laeuft & ist healthy.
#
# Aufruf:
#   ./run.sh                            # alle Gruppen
#   OBS_GROUPS="metrics traces" ./run.sh # nur ausgewaehlte Gruppen
#   ./run.sh --only "logs promql"       # dito per Argument
#   RUN_TELEMETRYGEN=false ./run.sh     # Pipeline-Checks (E1-E3) werden geskippt
#
# Hinweis: NICHT die Env-Variable GROUPS verwenden – das ist eine spezielle
# Bash-Variable (Gruppen-IDs des Users). Daher OBS_GROUPS bzw. --only.
#
# Exit 0 = kein Pflicht-Check fehlgeschlagen (Skips zaehlen nicht als Fehler).
# ---------------------------------------------------------------------------
set -uo pipefail
cd "$(dirname "$0")" || exit 2

# --- Helfer & Checks einbinden ----------------------------------------------
# shellcheck source=lib.sh
source ./lib.sh
for f in checks_metrics.sh checks_promql.sh checks_traces.sh checks_logs.sh \
         checks_correlation.sh checks_pipeline.sh checks_infra.sh checks_freshness.sh; do
  # shellcheck disable=SC1090
  source "./$f"
done

ALL_GROUPS="infra metrics promql traces logs correlation freshness pipeline"

# Gruppen-Auswahl via --only/-o Argument oder OBS_GROUPS-Env, sonst alle.
# (GROUPS ist in Bash reserviert und daher hier bewusst nicht als Env genutzt.)
SEL_GROUPS="${OBS_GROUPS:-}"
if [ "${1:-}" = "--only" ] || [ "${1:-}" = "-o" ]; then
  SEL_GROUPS="${2:-}"
fi
[ -z "$SEL_GROUPS" ] && SEL_GROUPS="$ALL_GROUPS"

# --- Preflight: Werkzeuge ----------------------------------------------------
missing=""
for tool in curl jq; do
  command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
done
if [ -n "$missing" ]; then
  printf "${C_RED}FEHLER:${C_OFF} benoetigte Werkzeuge fehlen:%s\n" "$missing" >&2
  exit 2
fi

printf "${C_BOLD}== Observability-Suite (curl+bash) ==${C_OFF}\n"
printf "Ziele: backend=%s prom=%s tempo=%s loki=%s grafana=%s\n\n" \
  "$BACKEND_URL" "$PROM_URL" "$TEMPO_URL" "$LOKI_URL" "$GRAFANA_URL"

# --- Readiness-Gate ----------------------------------------------------------
readiness_gate() {
  local deadline=$(( $(date +%s) + 90 ))
  local names=("Backend readiness" "Prometheus" "Tempo" "Loki" "Grafana")
  local urls=("$BACKEND_URL/actuator/health/readiness" "$PROM_URL/-/ready" \
              "$TEMPO_URL/ready" "$LOKI_URL/ready" "$GRAFANA_URL/api/health")
  local i code all
  while :; do
    all=1
    for i in "${!urls[@]}"; do
      code=$(http_code "${urls[$i]}" 2>/dev/null || echo "000")
      if [ "$code" != "200" ]; then all=0; LAST_STATE="${names[$i]}=$code"; fi
    done
    [ "$all" = 1 ] && return 0
    [ "$(date +%s)" -ge "$deadline" ] && return 1
    sleep 3
  done
}

printf "Warte auf Readiness aller Dienste ...\n"
if ! readiness_gate; then
  printf "${C_RED}FEHLER:${C_OFF} Stack nicht bereit (Readiness-Gate). Letzter Zustand: %s\n" "${LAST_STATE:-?}" >&2
  exit 2
fi
printf "${C_GREEN}Readiness OK.${C_OFF}\n\n"

# --- Traffic einmalig (wie traffic-Fixture) ---------------------------------
RUN_ID="$(date +%s)-${RANDOM}"
CUSTOMER="obs-bash-${RUN_ID}"
export RUN_ID CUSTOMER

generate_traffic() {
  local n code i
  n=$(curl -s --max-time "$HTTP_TIMEOUT" "$BACKEND_URL/api/products" | jq 'length' 2>/dev/null || echo 0)
  if ! [ "${n:-0}" -ge 1 ] 2>/dev/null; then
    printf "${C_RED}FEHLER:${C_OFF} DB leer – /api/products liefert keine Produkte.\n" >&2
    return 1
  fi
  # 2 gueltige Bestellungen mit eindeutigem Kunden.
  for i in 1 2; do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time "$HTTP_TIMEOUT" \
      -X POST "$BACKEND_URL/api/orders" -H 'Content-Type: application/json' \
      -d "{\"customerName\":\"$CUSTOMER\",\"items\":[{\"productId\":1,\"quantity\":2}]}")
    [ "$code" = "201" ] || { printf "${C_RED}FEHLER:${C_OFF} gueltige Bestellung != 201 (war %s)\n" "$code" >&2; return 1; }
  done
  # 1 ungueltige Bestellung (productId 99999 -> 404).
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time "$HTTP_TIMEOUT" \
    -X POST "$BACKEND_URL/api/orders" -H 'Content-Type: application/json' \
    -d "{\"customerName\":\"$CUSTOMER\",\"items\":[{\"productId\":99999,\"quantity\":1}]}")
  [ "$code" = "404" ] || { printf "${C_RED}FEHLER:${C_OFF} ungueltige Bestellung != 404 (war %s)\n" "$code" >&2; return 1; }
  # Ein paar Lese-Requests.
  curl -s -o /dev/null --max-time "$HTTP_TIMEOUT" "$BACKEND_URL/api/products"
  curl -s -o /dev/null --max-time "$HTTP_TIMEOUT" "$BACKEND_URL/api/products"
  curl -s -o /dev/null --max-time "$HTTP_TIMEOUT" "$BACKEND_URL/api/products/1"
  return 0
}

printf "Erzeuge Traffic (RUN_ID=%s, customer=%s) ...\n" "$RUN_ID" "$CUSTOMER"
if ! generate_traffic; then
  exit 2
fi
printf "${C_GREEN}Traffic erzeugt.${C_OFF}\n\n"

# --- Checks ausfuehren -------------------------------------------------------
for g in $SEL_GROUPS; do
  case "$g" in
    infra|metrics|promql|traces|logs|correlation|freshness|pipeline)
      printf "%b-- Gruppe: %s --%b\n" "$C_BOLD" "$g" "$C_OFF"
      "run_group_$g"
      printf "\n"
      ;;
    *)
      printf "${C_YELLOW}Hinweis:${C_OFF} unbekannte Gruppe '%s' – ignoriert.\n" "$g"
      ;;
  esac
done

# --- Zusammenfassung ---------------------------------------------------------
printf "${C_BOLD}== Zusammenfassung ==${C_OFF}\n"
printf "  ${C_GREEN}gruen:${C_OFF} %d   ${C_YELLOW}uebersprungen:${C_OFF} %d   ${C_RED}fehlgeschlagen:${C_OFF} %d\n" \
  "$PASS_N" "$SKIP_N" "$FAIL_N"

if [ "$FAIL_N" -gt 0 ]; then
  printf "\n${C_RED}Fehlgeschlagene Checks:${C_OFF}"
  printf "%b\n" "$FAILED_LIST"
  printf "\n${C_RED}Ergebnis: FEHLGESCHLAGEN${C_OFF}\n"
  exit 1
fi

printf "\n${C_GREEN}Ergebnis: ALLE PFLICHT-CHECKS GRUEN${C_OFF}\n"
exit 0

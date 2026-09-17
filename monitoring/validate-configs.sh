#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Statische Validierung aller Observability-Configs des Monitoring-Stacks.
# (Testart 7 – Config-Validierung). Lokal & CI-tauglich: nicht-interaktiv,
# Exit-Code-basiert. ALLE Checks laufen durch; Fehler werden gesammelt und
# fuehren erst am Ende zu Exit-Code 1.
#
# Aufruf:   ./validate-configs.sh
# Exit 0 = alle Pflicht-Checks gruen (best-effort-"uebersprungen" zaehlt nicht).
# Exit 1 = mindestens ein Pflicht-Check ist fehlgeschlagen.
# ---------------------------------------------------------------------------

# Kein 'set -e': ein fehlgeschlagener Check darf die restlichen nicht abbrechen.
set -uo pipefail

# In das Verzeichnis dieses Skripts wechseln (Configs liegen relativ dazu).
cd "$(dirname "$0")" || exit 2

# Verwendete Images (identisch zu docker-compose.yml). Bewusst auf feste
# Versionen gepinnt: mit :latest validiert dieses Skript sonst gegen eine
# andere Version als der Stack tatsaechlich faehrt - und ein Major-Upgrade
# rutscht unbemerkt herein (siehe Tempo 2.x -> 3.0).
IMG_PROM="prom/prometheus:v3.14.0"
IMG_OTEL="otel/opentelemetry-collector-contrib:0.160.0"
IMG_LOKI="grafana/loki:3.7.7"
IMG_TEMPO="grafana/tempo:3.0.0"
IMG_ALLOY="grafana/alloy:v1.19.2"

# Ergebnis-Sammler.
declare -a FAILED=()   # Pflicht-Checks, die fehlgeschlagen sind
declare -a PASSED=()   # gruene Checks
declare -a SKIPPED=()  # best-effort uebersprungen (kein Fehler)

# Farben nur, wenn Ausgabe ein Terminal ist (in CI automatisch aus).
if [ -t 1 ]; then
  C_GREEN="\033[0;32m"; C_RED="\033[0;31m"; C_YELLOW="\033[0;33m"; C_BOLD="\033[1m"; C_OFF="\033[0m"
else
  C_GREEN=""; C_RED=""; C_YELLOW=""; C_BOLD=""; C_OFF=""
fi

pass() { PASSED+=("$1");  printf "${C_GREEN}\xE2\x9C\x93${C_OFF} %s\n" "$1"; }
fail() { FAILED+=("$1");  printf "${C_RED}\xE2\x9C\x97${C_OFF} %s\n" "$1"; }
skip() { SKIPPED+=("$1"); printf "${C_YELLOW}\xE2\x9A\xA0${C_OFF} %s ${C_YELLOW}(uebersprungen)${C_OFF}\n" "$1"; }

# Zeigt die letzten Zeilen der gesammelten Toolausgabe eingerueckt an.
show_output() { sed 's/^/    | /' "$1" | tail -n 8; }

# Pflicht-Check: Kommando ausfuehren; Exit != 0 -> Fehler.
#   $1 = Beschreibung, restliche Args = Kommando
run_check() {
  local desc="$1"; shift
  local out; out="$(mktemp)"
  if "$@" >"$out" 2>&1; then
    pass "$desc"
  else
    fail "$desc"
    show_output "$out"
  fi
  rm -f "$out"
}

# Best-effort-Check: Exit 0 -> gruen. Bei Fehler wird geprueft, ob das Tool das
# Flag/Kommando schlicht nicht kennt -> dann "uebersprungen" statt hartem Fail.
# Nur echte Config-Fehler zaehlen als Fehler.
run_best_effort() {
  local desc="$1"; shift
  local out; out="$(mktemp)"
  if "$@" >"$out" 2>&1; then
    pass "$desc"
  elif grep -qiE "unknown|not defined|flag provided but not defined|unrecognized|no such|invalid command|command not found|Usage:" "$out"; then
    skip "$desc – Flag/Kommando in dieser Image-Version nicht verfuegbar"
  else
    fail "$desc"
    show_output "$out"
  fi
  rm -f "$out"
}

# Guard fuer container-basierte Checks: ist docker nicht verfuegbar, wird der Check
# je nach Typ als Fehler (Pflicht: 'req') bzw. uebersprungen (best-effort: 'opt')
# markiert. $1 = req|opt, $2 = Beschreibung, Rest = auszufuehrendes Kommando.
docker_check() {
  local mode="$1" desc="$2"; shift 2
  if [ "$DOCKER_OK" -ne 1 ]; then
    case "$mode" in
      req) fail "$desc – docker nicht verfuegbar" ;;
      *)   skip "$desc – docker nicht verfuegbar" ;;
    esac
    return
  fi
  case "$mode" in
    req) run_check "$desc" "$@" ;;
    *)   run_best_effort "$desc" "$@" ;;
  esac
}

echo
printf "${C_BOLD}== Config-Validierung Monitoring-Stack ==${C_OFF}\n"
echo

# Docker-Verfuegbarkeit pruefen: alle Tool-Checks brauchen Container.
DOCKER_OK=1
if ! command -v docker >/dev/null 2>&1; then
  DOCKER_OK=0
  printf "${C_YELLOW}Hinweis:${C_OFF} 'docker' ist nicht installiert/erreichbar – "
  echo "alle container-basierten Checks (1-6) werden markiert."
  echo
fi
DOCKER_RUN=(docker run --rm -v "$PWD":/w)

# python3 fuer die YAML-/JSON-Lint-Checks (7/8).
PY_OK=1; command -v python3 >/dev/null 2>&1 || PY_OK=0

# ---- 1. Docker-Compose-Struktur (inkl. Merge mit Override) ------------------
# Compose-Dateien liegen im Projektwurzel (eine Ebene ueber diesem Skript);
# von dort greift auch der automatische Merge der docker-compose.override.yml.
docker_check req "1. docker compose config (Syntax/Struktur, inkl. Override)" \
  bash -c 'cd .. && docker compose config -q'

# ---- 2. Prometheus (Pflicht) ------------------------------------------------
# --entrypoint muss vor dem Image stehen, laesst sich aber an DOCKER_RUN anhaengen.
docker_check req "2. Prometheus: promtool check config" \
  "${DOCKER_RUN[@]}" --entrypoint promtool "$IMG_PROM" check config /w/prometheus.yml

# ---- 3. OpenTelemetry-Collector (Pflicht) -----------------------------------
docker_check req "3. OTel-Collector: validate --config" \
  "${DOCKER_RUN[@]}" "$IMG_OTEL" validate --config=/w/otel-collector-config.yaml

# ---- 4. Loki (best-effort) --------------------------------------------------
docker_check opt "4. Loki: -verify-config" \
  "${DOCKER_RUN[@]}" "$IMG_LOKI" -verify-config -config.file=/w/loki-config.yaml

# ---- 5. Tempo (best-effort) -------------------------------------------------
docker_check opt "5. Tempo: -config.verify" \
  "${DOCKER_RUN[@]}" "$IMG_TEMPO" -config.file=/w/tempo.yaml -config.verify=true

# ---- 6. Alloy (best-effort) -------------------------------------------------
docker_check opt "6. Alloy: validate" \
  "${DOCKER_RUN[@]}" "$IMG_ALLOY" validate /w/alloy-config.alloy

# ---- 7. YAML-Lint aller *.yml / *.yaml (inkl. grafana/provisioning) ---------
if [ "$PY_OK" -eq 1 ]; then
  yaml_out="$(mktemp)"; yaml_rc=0
  while IFS= read -r f; do
    if python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$f" 2>>"$yaml_out"; then
      :
    else
      echo "  -> Fehler in $f" >>"$yaml_out"; yaml_rc=1
    fi
  done < <(find . -type f \( -name '*.yml' -o -name '*.yaml' \) | sort)
  if [ "$yaml_rc" -eq 0 ]; then
    pass "7. YAML-Lint aller *.yml/*.yaml"
  else
    fail "7. YAML-Lint aller *.yml/*.yaml"
    show_output "$yaml_out"
  fi
  rm -f "$yaml_out"
else
  fail "7. YAML-Lint – python3 nicht verfuegbar"
fi

# ---- 8. JSON-Lint aller Dashboards ------------------------------------------
if [ "$PY_OK" -eq 1 ]; then
  json_out="$(mktemp)"; json_rc=0; json_found=0
  while IFS= read -r f; do
    json_found=1
    if python3 -m json.tool "$f" >/dev/null 2>>"$json_out"; then
      :
    else
      echo "  -> Fehler in $f" >>"$json_out"; json_rc=1
    fi
  done < <(find grafana/provisioning/dashboards -type f -name '*.json' 2>/dev/null | sort)
  if [ "$json_found" -eq 0 ]; then
    skip "8. JSON-Lint – keine Dashboard-JSONs gefunden"
  elif [ "$json_rc" -eq 0 ]; then
    pass "8. JSON-Lint aller Dashboards"
  else
    fail "8. JSON-Lint aller Dashboards"
    show_output "$json_out"
  fi
  rm -f "$json_out"
else
  fail "8. JSON-Lint – python3 nicht verfuegbar"
fi

# ---- 9. Prometheus-Alarmregeln (Pflicht) ------------------------------------
# Eigener Check, weil 'promtool check config' die Regeln NICHT mitprueft: das
# rule_files-Glob zeigt auf den Container-Pfad /etc/prometheus/rules, der beim
# Validieren nicht existiert - ein leeres Glob ist fuer promtool kein Fehler.
if [ -d rules ] && compgen -G "rules/*.yml" >/dev/null; then
  # promtool erwartet Dateien, kein Verzeichnis -> Glob auf dem Host aufloesen
  # und auf den Container-Pfad umschreiben.
  declare -a RULE_FILES=()
  while IFS= read -r f; do RULE_FILES+=("/w/${f#./}"); done \
    < <(find rules -maxdepth 1 -type f -name '*.yml' | sort)
  docker_check req "9. Prometheus: promtool check rules" \
    "${DOCKER_RUN[@]}" --entrypoint promtool "$IMG_PROM" check rules "${RULE_FILES[@]}"
else
  skip "9. promtool check rules – keine Regeldateien gefunden"
fi

# ---- Zusammenfassung --------------------------------------------------------
echo
printf "${C_BOLD}== Zusammenfassung ==${C_OFF}\n"
printf "  ${C_GREEN}gruen:${C_OFF} %d   ${C_YELLOW}uebersprungen:${C_OFF} %d   ${C_RED}fehlgeschlagen:${C_OFF} %d\n" \
  "${#PASSED[@]}" "${#SKIPPED[@]}" "${#FAILED[@]}"

if [ "${#FAILED[@]}" -gt 0 ]; then
  echo
  printf "${C_RED}Fehlgeschlagene Checks:${C_OFF}\n"
  for c in "${FAILED[@]}"; do echo "  - $c"; done
  echo
  printf "${C_RED}Ergebnis: FEHLGESCHLAGEN${C_OFF}\n"
  exit 1
fi

echo
printf "${C_GREEN}Ergebnis: ALLE PFLICHT-CHECKS GRUEN${C_OFF}\n"
exit 0

#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Demo-Schalter fuer das Szenario "verschwundene Metriken".
#
#   ./demo-absence.sh on      Business-Metriken verschwinden lassen
#   ./demo-absence.sh off     Normalzustand wiederherstellen
#   ./demo-absence.sh status  aktuellen Zustand + Alarme anzeigen
#
# Technisch wird ein metric_relabel_configs-Block im backend-Job von
# prometheus.yml ein-/auskommentiert und Prometheus per SIGHUP neu geladen
# (der Container laeuft ohne --web.enable-lifecycle, daher kein /-/reload).
# Fuer die Alarm-Regeln ist das ununterscheidbar davon, dass die
# Instrumentierung aus dem Code entfernt wurde - nur ohne Rebuild.
#
# Erwarteter Ablauf nach 'on': nach ~2-3 Minuten stehen
# BusinessMetrikOrdersCreatedFehlt und BusinessMetrikOrderValueFehlt auf
# firing (vorher kurz 'pending' wegen 'for: 1m').
# ---------------------------------------------------------------------------
set -uo pipefail
cd "$(dirname "$0")" || exit 2

CONFIG="prometheus.yml"
PROM_URL="${PROM_URL:-http://localhost:9090}"
# Die drei Zeilen des Relabel-Blocks, identifiziert ueber ihre Einrueckung.
BLOCK_RE='^( *)#(metric_relabel_configs:|  - source_labels: \[__name__\]|    regex: .orders_created_total|    action: drop)'

if [ ! -f "$CONFIG" ]; then
  echo "FEHLER: $CONFIG nicht gefunden." >&2; exit 2
fi

# Ist der Block aktuell aktiv (= nicht auskommentiert)?
is_on() { grep -qE '^ *metric_relabel_configs:' "$CONFIG"; }

# WICHTIG: prometheus.yml ist als EINZELNE Datei in den Container gemountet.
# Docker bindet dabei den Inode, nicht den Pfad. 'sed -i' legt eine neue Datei
# an und ersetzt die alte - der Container sieht die Aenderung dann nie (im
# schlimmsten Fall zeigt sein Mount auf einen geloeschten Inode). Deshalb wird
# hier ueber eine Temp-Datei umgeschrieben und der Inhalt per Redirect
# ZURUECKGESCHRIEBEN: '> "$CONFIG"' kuerzt die bestehende Datei und behaelt
# ihren Inode.
apply_sed() {
  local expr="$1" tmp
  tmp="$(mktemp)" || return 1
  sed -E "$expr" "$CONFIG" >"$tmp" || { rm -f "$tmp"; return 1; }
  cat "$tmp" >"$CONFIG" || { rm -f "$tmp"; return 1; }
  rm -f "$tmp"
}

# Zeitpunkt des letzten erfolgreichen Config-Reloads (Unix-Sekunden).
reload_ts() {
  curl -s --max-time 5 \
    "$PROM_URL/api/v1/query?query=prometheus_config_last_reload_success_timestamp_seconds" \
    | sed -n 's/.*"value":\[[^,]*,"\([^"]*\)".*/\1/p'
}

reload_prometheus() {
  if ! docker ps --format '{{.Names}}' | grep -qx prometheus; then
    echo "WARNUNG: Container 'prometheus' laeuft nicht - Config geaendert, aber kein Reload." >&2
    return 1
  fi
  # Gegenprobe, dass der Container die geaenderte Datei ueberhaupt sieht. Faengt
  # einen kaputten Einzeldatei-Mount (siehe Kommentar bei apply_sed) sofort ab,
  # statt ihn als stillen Nicht-Effekt durchgehen zu lassen.
  if ! docker exec prometheus test -f /etc/prometheus/prometheus.yml 2>/dev/null; then
    echo "FEHLER: Der Container sieht /etc/prometheus/prometheus.yml nicht mehr." >&2
    echo "       Der Einzeldatei-Mount ist entkoppelt. Reparatur:" >&2
    echo "       docker compose up -d --force-recreate prometheus" >&2
    return 1
  fi

  local before after
  before="$(reload_ts)"
  docker kill -s HUP prometheus >/dev/null || {
    echo "FEHLER: SIGHUP an Prometheus fehlgeschlagen." >&2; return 1; }
  sleep 3
  after="$(reload_ts)"
  # Nur ein GESTIEGENER Zeitstempel beweist, dass wirklich neu geladen wurde.
  # 'prometheus_config_last_reload_successful' taugt dafuer nicht: die Metrik
  # steht auch ohne jeden Reload seit dem Start auf 1.
  if [ -n "$after" ] && [ "$after" != "$before" ]; then
    echo "Prometheus-Reload erfolgreich (Config neu eingelesen)."
  else
    echo "FEHLER: Prometheus hat die Config nicht neu geladen oder abgelehnt." >&2
    echo "       Details: docker logs --tail 20 prometheus" >&2
    return 1
  fi
}

case "${1:-}" in
  on)
    if is_on; then
      echo "Szenario laeuft bereits (Metriken werden verworfen)."
    else
      # '#' am Zeilenanfang des Blocks entfernen.
      apply_sed "s/$BLOCK_RE/\1\2/" || { echo "FEHLER: Schreiben fehlgeschlagen." >&2; exit 1; }
      is_on || { echo "FEHLER: Block konnte nicht aktiviert werden." >&2; exit 1; }
      echo "Szenario AKTIV: orders_created_total und order_value_euros* werden beim Scrape verworfen."
    fi
    reload_prometheus || exit 1
    echo
    echo "Naechste Schritte:"
    echo "  - ~2-3 Min warten, dann $PROM_URL/alerts oeffnen"
    echo "  - erwartet: BusinessMetrikOrdersCreatedFehlt + BusinessMetrikOrderValueFehlt = firing"
    echo "  - Kontrast: das Grafana-Panel zeigt dabei nur ein leeres Diagramm"
    echo "  - danach: ./demo-absence.sh off"
    ;;
  off)
    if is_on; then
      # Block wieder auskommentieren.
      apply_sed 's/^( *)(metric_relabel_configs:|  - source_labels: \[__name__\]|    regex: .orders_created_total|    action: drop)/\1#\2/' \
        || { echo "FEHLER: Schreiben fehlgeschlagen." >&2; exit 1; }
      is_on && { echo "FEHLER: Block konnte nicht deaktiviert werden." >&2; exit 1; }
      echo "Szenario BEENDET: Metriken werden wieder uebernommen."
    else
      echo "Szenario war nicht aktiv - nichts zu tun."
    fi
    reload_prometheus || exit 1
    echo "Die Alarme wechseln nach dem naechsten Scrape zurueck auf 'inactive'."
    ;;
  status)
    if is_on; then
      echo "Zustand: SZENARIO AKTIV (Business-Metriken werden verworfen)"
    else
      echo "Zustand: normal (Business-Metriken werden uebernommen)"
    fi
    echo
    echo "-- Serie vorhanden? --"
    curl -s --max-time 5 "$PROM_URL/api/v1/query?query=orders_created_total" \
      | grep -q '"result":\[\]' && echo "  orders_created_total: FEHLT" || echo "  orders_created_total: vorhanden"
    echo
    echo "-- Regelzustand --"
    # Bewusst ueber /api/v1/rules statt /api/v1/alerts: zeigt auch die
    # inaktiven Regeln, was fuer die Demo der halbe Punkt ist.
    # jq ist noetig - ein sed-Muster ueber das einzeilige JSON ist greedy und
    # liefert nur den jeweils letzten Treffer.
    if command -v jq >/dev/null 2>&1; then
      curl -s --max-time 5 "$PROM_URL/api/v1/rules" \
        | jq -r '.data.groups[].rules[] | "  \(.state | ascii_upcase | .[0:8] | . + "        " | .[0:8]) \(.name)"'
    else
      echo "  (jq nicht installiert - Zustand unter $PROM_URL/alerts einsehen)"
    fi
    ;;
  *)
    sed -n '3,8p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac

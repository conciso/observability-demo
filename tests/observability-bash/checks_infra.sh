# shellcheck shell=bash
# Infrastruktur-Checks: A8 (Prometheus-Targets), F2 (Grafana/Datasources).

check_a8() {
  local json down
  json=$(curl -s --max-time "$HTTP_TIMEOUT" "$PROM_URL/api/v1/targets")
  if ! printf '%s' "$json" | jq -e '.data.activeTargets | length > 0' >/dev/null; then
    fail "A8: keine aktiven Prometheus-Targets"
    return 0
  fi
  # node-exporter nur strikt pruefen, wenn STRICT_NODE_EXPORTER=true.
  down=$(printf '%s' "$json" | jq -r --arg strict "$STRICT_NODE_EXPORTER" '
    [ .data.activeTargets[]
      | select(.health != "up")
      | select(.labels.job != "node-exporter" or $strict == "true")
      | "\(.labels.job)=\(.health)" ] | join(", ")')
  if [ -z "$down" ]; then
    pass "A8: alle Prometheus-Targets 'up' (node-exporter strict=$STRICT_NODE_EXPORTER)"
  else
    fail "A8: Targets nicht 'up'" "$down"
  fi
}

check_f2() {
  local code ds ok=1
  # Grafana-Health (ohne Auth).
  code=$(http_code "$GRAFANA_URL/api/health")
  if [ "$code" != "200" ]; then
    fail "F2: Grafana /api/health" "war $code"
    return 0
  fi
  # Datasources vorhanden (BasicAuth).
  ds=$(curl -s --max-time "$HTTP_TIMEOUT" -u "$GRAFANA_USER:$GRAFANA_PASS" "$GRAFANA_URL/api/datasources")
  local t
  for t in prometheus loki tempo; do
    if ! printf '%s' "$ds" | jq -e --arg t "$t" 'any(.[]; .type == $t)' >/dev/null 2>&1; then
      ok=0; fail "F2: Datasource-Typ fehlt: $t"
    fi
  done
  # Datasource-Health je uid – tolerant (nur pruefen, falls Endpoint 200 liefert).
  local uid hcode status
  for uid in prometheus loki tempo; do
    hcode=$(curl -s -o /tmp/f2_ds_$$.json -w '%{http_code}' --max-time "$HTTP_TIMEOUT" \
      -u "$GRAFANA_USER:$GRAFANA_PASS" "$GRAFANA_URL/api/datasources/uid/$uid/health")
    if [ "$hcode" = "200" ]; then
      status=$(jq -r '.status // ""' /tmp/f2_ds_$$.json | tr 'a-z' 'A-Z')
      if [ "$status" != "OK" ]; then ok=0; fail "F2: Datasource $uid health status = $status"; fi
    fi
    rm -f /tmp/f2_ds_$$.json
  done
  [ "$ok" = 1 ] && pass "F2: Grafana healthy + Datasources prometheus/loki/tempo vorhanden"
}

run_group_infra() { check_a8; check_f2; }

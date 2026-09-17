# shellcheck shell=bash
# PromQL-Checks (rechnende Queries): A7, rate, histogram_quantile p95,
# sum by(status), Ø-Bestellwert. Grosszuegige Timeouts (~60s) wegen 15s-Scrape.

_a7_delta_reached() {  # nutzt $A7_TARGET (dynamischer Scope)
  local v; v=$(promql_instant_sum "orders_created_total")
  fge "$v" "$A7_TARGET"
}

_a7_have_start() {  # Startwert vorhanden und > 0
  local v; v=$(promql_instant_sum "orders_created_total")
  [ -n "$v" ] && fgt "$v" 0
}

check_a7() {
  local customer="obs-bash-promql-${RUN_ID}" M=2 v0
  # Startwert (retry bis ueberhaupt ein Wert da ist).
  if ! retry 60 3 _a7_have_start; then
    fail "A7: kein Startwert orders_created_total in Prometheus"
    return 0
  fi
  v0=$(promql_instant_sum "orders_created_total")
  if ! place_orders "$customer" "$M"; then
    fail "A7: konnte $M Bestellungen nicht absetzen"
    return 0
  fi
  A7_V0="$v0"; A7_TARGET=$(awk "BEGIN{print $v0 + $M}")
  if retry 60 3 _a7_delta_reached; then
    local v1; v1=$(promql_instant_sum "orders_created_total")
    pass "A7: Scrape-Delta orders_created_total $v0 -> $v1 (>= +$M)"
  else
    fail "A7: orders_created_total stieg nicht um >= $M (Start $v0)"
  fi
}

_rate_total_pos() {
  local v; v=$(promql_instant_sum "sum(rate(http_server_requests_seconds_count[5m]))")
  fgt "$v" 0
}
_rate_orders_nonempty() {
  [ "$(promql_count 'rate(http_server_requests_seconds_count{uri="/api/orders"}[5m])')" -ge 1 ]
}

check_rate() {
  if retry 60 3 _rate_total_pos && retry 60 3 _rate_orders_nonempty; then
    pass "rate(): Gesamt-Request-Rate > 0 und rate fuer /api/orders nicht leer"
  else
    fail "rate(): Request-Rate nicht > 0 bzw. /api/orders leer"
  fi
}

_p95_finite_pos() {
  local q="histogram_quantile(0.95, sum by (le) (rate(order_value_euros_bucket[5m])))"
  local json n val
  json=$(promql_raw "$q")
  n=$(printf '%s' "$json" | jq -r '.data.result | length')
  [ "$n" = "1" ] || return 1
  val=$(printf '%s' "$json" | jq -r '.data.result[0].value[1]')
  case "$val" in NaN|+Inf|-Inf|Inf) return 1 ;; esac
  fgt "$val" 0
}

check_p95() {
  # Frische Bestellungen, damit die Buckets im 5m-rate-Fenster ansteigen (sonst NaN).
  place_orders "obs-bash-p95-${RUN_ID}" 3 || true
  if retry 60 3 _p95_finite_pos; then
    pass "histogram_quantile p95(order_value_euros): genau 1 Element, endlich und > 0"
  else
    fail "histogram_quantile p95(order_value_euros) nicht endlich/positiv"
  fi
}

_sum_by_status_201() {
  promql_raw 'sum by (status) (http_server_requests_seconds_count{uri="/api/orders"})' \
    | jq -e '[.data.result[] | select(.metric.status == "201") | (.value[1]|tonumber)] | any(. >= 1)' >/dev/null
}

check_sum_by_status() {
  if retry 60 3 _sum_by_status_201; then
    pass "sum by(status) /api/orders enthaelt status=201 mit Wert >= 1"
  else
    fail "sum by(status) /api/orders ohne status=201 >= 1"
  fi
}

_avg_finite_pos() {
  promql_raw 'order_value_euros_sum / order_value_euros_count' \
    | jq -e '[.data.result[].value[1]
             | select(. != "NaN" and . != "+Inf" and . != "-Inf" and . != "Inf")
             | tonumber | select(. > 0)] | length >= 1' >/dev/null
}

check_avg() {
  if retry 60 3 _avg_finite_pos; then
    pass "Ø-Bestellwert (order_value_euros_sum/_count): endlich und > 0"
  else
    fail "Ø-Bestellwert nicht endlich/positiv"
  fi
}

run_group_promql() { check_a7; check_rate; check_p95; check_sum_by_status; check_avg; }

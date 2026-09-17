# shellcheck shell=bash
# G3: Freshness – juengste Metrik/Trace/Log innerhalb der letzten ~10 Minuten.

MAX_AGE_S=600  # 10 Minuten

_g3_prom_fresh() {
  local ts now
  ts=$(promql_raw "orders_created_total" \
       | jq -r '[.data.result[].value[0]] | max // empty')
  [ -n "$ts" ] || return 1
  now=$(date +%s)
  awk "BEGIN{exit !(($now - $ts) < $MAX_AGE_S)}"
}
check_g3_prom() {
  if retry 30 3 _g3_prom_fresh; then
    pass "G3/Prometheus: juengster orders_created_total-Wert < ${MAX_AGE_S}s alt"
  else
    fail "G3/Prometheus: kein frischer Wert"
  fi
}

_g3_tempo_fresh() {
  local newest_ns now
  newest_ns=$(tempo_search '{ resource.service.name = "food-order-backend" }' 20 \
              | jq -r '[.traces[]?.startTimeUnixNano | tonumber] | max // empty')
  [ -n "$newest_ns" ] || return 1
  now=$(date +%s)
  awk "BEGIN{exit !(($now - $newest_ns/1000000000) < $MAX_AGE_S)}"
}
check_g3_tempo() {
  if retry 30 3 _g3_tempo_fresh; then
    pass "G3/Tempo: juengster Trace < ${MAX_AGE_S}s alt"
  else
    fail "G3/Tempo: kein frischer Trace"
  fi
}

_g3_loki_fresh() {
  local newest_ns now
  newest_ns=$(loki_query_range "{service_name=\"$SVC\"}" 10 \
              | jq -r '[.data.result[].values[][0] | tonumber] | max // empty')
  [ -n "$newest_ns" ] || return 1
  now=$(date +%s)
  awk "BEGIN{exit !(($now - $newest_ns/1000000000) < $MAX_AGE_S)}"
}
check_g3_loki() {
  if retry 30 3 _g3_loki_fresh; then
    pass "G3/Loki: juengste Logzeile < ${MAX_AGE_S}s alt"
  else
    fail "G3/Loki: keine frische Logzeile"
  fi
}

run_group_freshness() { check_g3_prom; check_g3_tempo; check_g3_loki; }

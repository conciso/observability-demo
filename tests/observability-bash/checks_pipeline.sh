# shellcheck shell=bash
# telemetrygen-Pipeline: E1 (Traces->Tempo), E2 (Logs->Loki), E3 (Metrics->Prometheus).
# Gate: RUN_TELEMETRYGEN + docker + Compose-Netz -> sonst sauberer Skip.

PIPE_NET=""

_pipeline_gate() {  # setzt $PIPE_NET; gibt Skip-Grund in $PIPE_SKIP zurueck
  PIPE_SKIP=""
  if [ "$RUN_TELEMETRYGEN" != "true" ]; then PIPE_SKIP="RUN_TELEMETRYGEN=false"; return 1; fi
  if ! command -v docker >/dev/null 2>&1; then PIPE_SKIP="docker nicht verfuegbar"; return 1; fi
  PIPE_NET=$(find_monitoring_network) || { PIPE_SKIP="Compose-Netz 'monitoring' nicht gefunden"; return 1; }
  [ -n "$PIPE_NET" ] || { PIPE_SKIP="Compose-Netz 'monitoring' nicht gefunden"; return 1; }
  return 0
}

_run_telemetrygen() {  # <signal> <service> <extra-args...>
  local signal="$1" service="$2"; shift 2
  docker run --rm --network "$PIPE_NET" "$TELEMETRYGEN_IMAGE" \
    "$signal" --otlp-endpoint otel-collector:4317 --otlp-insecure \
    --service "$service" "$@" >/dev/null 2>&1
}

check_e1() {
  if ! _pipeline_gate; then skip "E1: telemetrygen Traces->Tempo – $PIPE_SKIP"; return 0; fi
  local service="telemetrygen-ci-${RUN_ID}"
  if ! _run_telemetrygen traces "$service" --traces 5; then
    skip "E1: telemetrygen traces nicht ausfuehrbar (Image/Netz?)"; return 0
  fi
  if retry 30 3 _tempo_ge1 "{ resource.service.name = \"$service\" }"; then
    pass "E1: telemetrygen-Traces in Tempo ($service)"
  else
    fail "E1: keine telemetrygen-Traces in Tempo ($service)"
  fi
}

_e2_logs_present() {  # nutzt $E2_SERVICE
  [ "$(loki_query_range "{service_name=\"$E2_SERVICE\"}" 10 | jq -r '.data.result | length')" -ge 1 ]
}
check_e2() {
  if ! _pipeline_gate; then skip "E2: telemetrygen Logs->Loki – $PIPE_SKIP"; return 0; fi
  E2_SERVICE="telemetrygen-logs-${RUN_ID}"
  if ! _run_telemetrygen logs "$E2_SERVICE" --logs 5 --body "e2e-log-${RUN_ID}"; then
    skip "E2: telemetrygen logs nicht ausfuehrbar (Image/Netz?)"; return 0
  fi
  if retry 60 3 _e2_logs_present; then
    pass "E2: telemetrygen-Logs in Loki (service_name=$E2_SERVICE)"
  else
    fail "E2: keine telemetrygen-Logs in Loki ($E2_SERVICE)"
  fi
}

_e3_metric_present() {  # nutzt $E3_SERVICE
  [ "$(promql_count "gen_total{exported_job=\"$E3_SERVICE\"}")" -ge 1 ]
}
check_e3() {
  if ! _pipeline_gate; then skip "E3: telemetrygen Metrics->Prometheus – $PIPE_SKIP"; return 0; fi
  E3_SERVICE="telemetrygen-metrics-${RUN_ID}"
  if ! _run_telemetrygen metrics "$E3_SERVICE" --metrics 5 --metric-type Sum; then
    skip "E3: telemetrygen metrics nicht ausfuehrbar (Image/Netz?)"; return 0
  fi
  # Grosszuegiger Timeout wegen 15s-Scrape-Intervall.
  if retry 60 3 _e3_metric_present; then
    pass "E3: telemetrygen-Metrik gen_total{exported_job=\"$E3_SERVICE\"} in Prometheus"
  else
    fail "E3: telemetrygen-Metrik nicht in Prometheus ($E3_SERVICE)"
  fi
}

run_group_pipeline() { check_e1; check_e2; check_e3; }

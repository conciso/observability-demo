# shellcheck shell=bash
# Log-Checks via Loki: C1 (Label), C2 (Inhalt), C3 (trace/span), C4 (Resource),
# C5 (Severity).

_c1_ok() {
  curl -s --max-time "$HTTP_TIMEOUT" "$LOKI_URL/loki/api/v1/label/service_name/values" \
    | jq -e --arg svc "$SVC" '(.data // []) | index($svc) != null' >/dev/null
}
check_c1() {
  if retry 30 3 _c1_ok; then
    pass "C1: Loki-Label service_name=$SVC vorhanden"
  else
    fail "C1: Loki-Label service_name=$SVC fehlt"
  fi
}

_c2_ok() {
  loki_query_range "{service_name=\"$SVC\"}" 50 \
    | jq -e '[.data.result[].values[][1] | select(test("Created order"))] | length >= 1' >/dev/null
}
check_c2() {
  if retry 30 3 _c2_ok; then
    pass "C2: Logzeile 'Created order' vorhanden"
  else
    fail "C2: keine 'Created order'-Logzeile"
  fi
}

_c3_ok() {
  loki_query_range "{service_name=\"$SVC\"} | trace_id != \"\"" 10 \
    | jq -e '[.data.result[] | select((.stream.trace_id // "") != "" and (.stream.span_id // "") != "")] | length >= 1' >/dev/null
}
check_c3() {
  if retry 30 3 _c3_ok; then
    pass "C3: Stream-Labels mit nicht-leerer trace_id UND span_id"
  else
    fail "C3: kein Stream mit trace_id & span_id"
  fi
}

_c4_ok() {
  loki_query_range "{service_name=\"$SVC\"}" 10 \
    | jq -e '[.data.result[] | select((.stream.service_namespace // "") != ""
            and (.stream.deployment_environment // "") != ""
            and (.stream.service_version // "") != "")] | length >= 1' >/dev/null
}
check_c4() {
  if retry 30 3 _c4_ok; then
    pass "C4: Resource-Labels (service_namespace, deployment_environment, service_version)"
  else
    fail "C4: Resource-Labels fehlen/leer"
  fi
}

_c5_ok() {
  loki_query_range "{service_name=\"$SVC\"}" 20 | jq -e '
    ["TRACE","DEBUG","INFO","WARN","WARNING","ERROR","FATAL"] as $allowed
    | [.data.result[]
       | ((.stream.severity_text // .stream.detected_level // "") | ascii_upcase)
       | select(. as $s | $allowed | index($s) != null)] | length >= 1' >/dev/null
}
check_c5() {
  if retry 30 3 _c5_ok; then
    pass "C5: Severity-Label (severity_text/detected_level) aus bekannter Menge"
  else
    fail "C5: kein gueltiges Severity-Label"
  fi
}

run_group_logs() { check_c1; check_c2; check_c3; check_c4; check_c5; }

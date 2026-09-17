# shellcheck shell=bash
# D1: Trace<->Log-Korrelation ueber den eindeutigen customer-Marker.

_d1_find_trace_id() {  # setzt $D1_TID aus der 'Created order'-Logzeile des Kunden
  D1_TID=$(loki_query_range "{service_name=\"$SVC\"} |= \"$CUSTOMER\"" 20 | jq -r '
    .data.result[]
    | select((.stream.trace_id // "") != "")
    | select([.values[][1] | select(test("Created order"))] | length > 0)
    | .stream.trace_id' | head -1)
  [ -n "$D1_TID" ]
}

_d1_verify_tempo() {  # nutzt $D1_TID; prueft Span POST /api/orders + gleiche traceID
  local json b64 hex
  json=$(curl -s --max-time "$HTTP_TIMEOUT" "$TEMPO_URL/api/traces/$D1_TID")
  [ -n "$json" ] || return 1
  # Span POST /api/orders muss vorhanden sein.
  printf '%s' "$json" | jq -e '[.batches[].scopeSpans[].spans[].name] | index("POST /api/orders") != null' >/dev/null || return 1
  # traceId aus OTLP-JSON ist base64 -> nach hex normalisieren und vergleichen.
  b64=$(printf '%s' "$json" | jq -r '[.batches[].scopeSpans[].spans[].traceId] | .[0] // empty')
  [ -n "$b64" ] || return 0   # kein traceId-Feld -> nur Span-Nachweis (wie im Original tolerant)
  hex=$(b64_to_hex "$b64")
  [ "$(printf '%s' "$hex" | tr 'A-F' 'a-f')" = "$(printf '%s' "$D1_TID" | tr 'A-F' 'a-f')" ]
}

check_d1() {
  # Tempo-Verify mit 90s (wie B3): frische Traces sind wegen WAL-Flush erst
  # verzoegert per /api/traces abrufbar; 30s waren im Vollauf gelegentlich flaky.
  if retry 30 3 _d1_find_trace_id && retry 90 3 _d1_verify_tempo; then
    pass "D1: Trace<->Log-Korrelation ueber $CUSTOMER (trace_id=$D1_TID, Span POST /api/orders)"
  else
    fail "D1: Korrelation Log->Tempo fehlgeschlagen (customer=$CUSTOMER, trace_id=${D1_TID:-<none>})"
  fi
}

run_group_correlation() { check_d1; }

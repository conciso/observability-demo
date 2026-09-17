# shellcheck shell=bash
# Trace-Checks via Tempo: B1, B2, B5, B4 (+ B4-Business=skip), B3.

_tempo_ge1() { [ "$(tempo_count "$1" 5)" -ge 1 ]; }

check_b1() {
  if retry 30 3 _tempo_ge1 '{ resource.service.name = "food-order-backend" }'; then
    pass "B1: Traces fuer food-order-backend vorhanden"
  else
    fail "B1: keine Traces fuer food-order-backend"
  fi
}

check_b2() {
  local ok=1 name
  for name in "POST /api/orders" "GET /api/products"; do
    if ! retry 30 3 _tempo_ge1 "{ resource.service.name=\"food-order-backend\" && name=\"$name\" }"; then
      ok=0; fail "B2: kein Trace mit Span-Name '$name'"
    fi
  done
  [ "$ok" = 1 ] && pass "B2: Traces fuer Span-Namen POST /api/orders & GET /api/products"
}

_b5_ok() {
  tempo_search '{ resource.service.name = "food-order-backend" }' 5 | jq -e '
    (.traces // []) as $t
    | ($t | length >= 1)
      and ($t | all(
          ( .durationMs
            // ( ( .spanSet.spans[0].durationNanos // "0" ) | tonumber / 1000000 )
          ) as $d | ($d > 0 and $d < 60000)
        ))' >/dev/null
}

check_b5() {
  if retry 30 3 _b5_ok; then
    pass "B5: Trace-Dauer plausibel (0 < durationMs < 60000)"
  else
    fail "B5: Trace-Dauer unplausibel oder keine Traces"
  fi
}

# --- B4: Span-/Resource-Attribute -------------------------------------------
_b4_resource_filters() {
  _tempo_ge1 '{ resource.service.name = "food-order-backend" }' \
    && _tempo_ge1 '{ resource.service.namespace = "food-order" }' \
    && _tempo_ge1 '{ resource.deployment.environment = "demo" }'
}
_b4_http_filters() {
  _tempo_ge1 '{ resource.service.name="food-order-backend" && span.http.request.method = "POST" }' \
    && _tempo_ge1 '{ resource.service.name="food-order-backend" && span.http.response.status_code = 201 }'
}
_b4_deep_ok() {
  local tid
  tid=$(tempo_search '{ resource.service.name="food-order-backend" && name="POST /api/orders" }' 1 \
        | jq -r '.traces[0].traceID // empty')
  [ -n "$tid" ] || return 1
  curl -s --max-time "$HTTP_TIMEOUT" "$TEMPO_URL/api/traces/$tid" | jq -e '
    ([.batches[].resource.attributes[].key]) as $rk
    | ([.batches[].scopeSpans[].spans[].attributes[]?.key]) as $sk
    | ((["service.name","service.namespace","deployment.environment","telemetry.sdk.language"] - $rk) | length == 0)
      and (($sk | index("http.request.method")) != null)
      and (($sk | index("http.response.status_code")) != null)
  ' >/dev/null
}

check_b4() {
  if retry 30 3 _b4_resource_filters && retry 30 3 _b4_http_filters && retry 30 3 _b4_deep_ok; then
    pass "B4: Resource- & HTTP-Span-Attribute (Semantic Convention) vorhanden"
  else
    fail "B4: erwartete Span-/Resource-Attribute fehlen"
  fi
}

check_b4_business() {
  # Bewusst als Skip: order.item_count wird vom OTel-Agent nur als Metrik, nicht
  # als Span-Attribut exportiert (empirisch verifiziert, wie in der pytest-Suite).
  if [ "$(tempo_count '{ span.order.item_count > 0 }' 5)" -ge 1 ]; then
    pass "B4-Business: span.order.item_count > 0 vorhanden (unerwartet, aber ok)"
  else
    skip "B4-Business: order.item_count ist kein Span-Attribut (nur Metrik) – wie in pytest-Suite"
  fi
}

# --- B3: Trace-Tiefe (HTTP + DB) --------------------------------------------
_b3_get_post_tid() {
  B3_TID=$(tempo_search '{ resource.service.name="food-order-backend" && name="POST /api/orders" }' 1 \
           | jq -r '.traces[0].traceID // empty')
  [ -n "$B3_TID" ]
}
_b3_depth_ok() {  # nutzt $B3_TID
  curl -s --max-time "$HTTP_TIMEOUT" "$TEMPO_URL/api/traces/$B3_TID" | jq -e '
    ([.batches[].scopeSpans[].spans[]] | length > 1)
    and (
      (([.batches[].scopeSpans[].spans[].attributes[]?.key] | index("http.request.method")) != null)
      or ([.batches[].scopeSpans[].scope.name] | map(test("tomcat")) | any)
    )
    and (
      (([.batches[].scopeSpans[].spans[].attributes[]?.key]
         | (index("db.system") != null or index("db.statement") != null)))
      or ([.batches[].scopeSpans[].scope.name] | map(test("jdbc")) | any)
    )
  ' >/dev/null
}

check_b3() {
  # Grosszuegiger Timeout (90s): frische Traces brauchen bis zum WAL-Flush.
  if retry 90 3 _b3_get_post_tid && retry 30 3 _b3_depth_ok; then
    pass "B3: Trace-Tiefe – > 1 Span mit HTTP-Server- UND DB-Span"
  else
    fail "B3: Trace nicht tief genug (HTTP+DB) oder nicht gefunden"
  fi
}

run_group_traces() { check_b1; check_b2; check_b5; check_b4; check_b4_business; check_b3; }

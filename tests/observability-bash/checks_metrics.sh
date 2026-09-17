# shellcheck shell=bash
# Metrik-Checks am Actuator-Endpoint: A1, A2, A6, A4.

# --- Probes ------------------------------------------------------------------
_a1_probe() {
  local text; text=$(actuator_text) || return 1
  printf '%s' "$text" | grep -q "# HELP" || return 1
  [ "$(printf '%s\n' "$text" | grep -cE '^[a-zA-Z_:][a-zA-Z0-9_:]*')" -ge 1 ]
}

_a2_probe() {
  local text; text=$(actuator_text) || return 1
  local m
  for m in orders_created_total order_value_euros_count order_value_euros_sum order_value_euros_bucket; do
    printf '%s\n' "$text" | grep -qE "^${m}[{ ]" || return 1
  done
}

_a6_probe() {
  local text; text=$(actuator_text) || return 1
  local m
  for m in jvm_memory_used_bytes jvm_threads_live_threads process_cpu_usage; do
    printf '%s\n' "$text" | grep -qE "^${m}[{ ]" || return 1
  done
}

# --- Checks ------------------------------------------------------------------
check_a1() {
  if retry 30 3 _a1_probe; then
    pass "A1: /actuator/prometheus parsebar (# HELP + >=1 Serie)"
  else
    fail "A1: /actuator/prometheus nicht parsebar"
  fi
}

check_a2() {
  if retry 30 3 _a2_probe; then
    pass "A2: Business-Serien vorhanden (orders_created_total, order_value_euros_*)"
  else
    fail "A2: Business-Serien fehlen"
  fi
}

check_a6() {
  if retry 30 3 _a6_probe; then
    pass "A6: JVM-/Prozess-Serien vorhanden"
  else
    fail "A6: JVM-/Prozess-Serien fehlen"
  fi
}

check_a4() {
  # Deterministisch ueber den Actuator-Text (Vor/Nach-Vergleich), KEINE gueltige
  # Bestellung im Test. Eine ungueltige Bestellung darf den Zaehler nicht erhoehen.
  local v0 v1 code
  v0=$(actuator_orders_total)
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time "$HTTP_TIMEOUT" \
    -X POST "$BACKEND_URL/api/orders" -H 'Content-Type: application/json' \
    -d '{"customerName":"a4-invalid","items":[{"productId":99999,"quantity":1}]}')
  if [ "$code" != "404" ]; then
    fail "A4: ungueltige Bestellung erwartet 404" "war $code"
    return 0
  fi
  v1=$(actuator_orders_total)
  if [ "$v0" = "$v1" ]; then
    pass "A4: fehlgeschlagene Bestellung zaehlt nicht (orders_created_total unveraendert: $v0)"
  else
    fail "A4: orders_created_total veraendert durch fehlgeschlagene Bestellung" "$v0 -> $v1"
  fi
}

run_group_metrics() { check_a1; check_a2; check_a6; check_a4; }

"""Gemeinsame Fixtures & Helfer fuer die Observability-Black-Box-Suite.

Getestet wird ausschliesslich ueber die Query-APIs des laufenden Stacks
(Backend, Prometheus, Tempo, Loki, Grafana) – kein App-Quellcode wird angefasst.
Asynchrone Telemetrie wird grundsaetzlich ueber `until()` abgewartet (keine festen
sleeps). Es werden keine absoluten Zaehlerwerte angenommen, sondern
Praesenz/Marker (eindeutiger `run_id`).
"""
import math
import os
import re
import time
import types
import uuid

import pytest
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

# --- Geteilte requests.Session (Keep-Alive + Retry) -------------------------
# Connection-Pooling gegen die vielen Poll-Requests von until(). Retry nur fuer
# transiente Connection-Fehler (connect=3), NICHT fuer HTTP-Statuscodes
# (status_forcelist leer) – die Assertions/until() bleiben massgeblich.
def _build_session():
    session = requests.Session()
    retry = Retry(
        total=None, connect=3, read=0, redirect=0, status=0,
        backoff_factor=0.3, status_forcelist=(),
    )
    adapter = HTTPAdapter(max_retries=retry)
    session.mount("http://", adapter)
    session.mount("https://", adapter)
    return session


# Modulweite Session, von allen conftest-Helfern und der `http`-Fixture genutzt.
SESSION = _build_session()

# --- Basis-URLs & Zugangsdaten aus Env (mit lokalen Defaults) ---------------
BACKEND_URL = os.environ.get("BACKEND_URL", "http://localhost:8081").rstrip("/")
PROM_URL = os.environ.get("PROM_URL", "http://localhost:9090").rstrip("/")
TEMPO_URL = os.environ.get("TEMPO_URL", "http://localhost:3200").rstrip("/")
LOKI_URL = os.environ.get("LOKI_URL", "http://localhost:3100").rstrip("/")
GRAFANA_URL = os.environ.get("GRAFANA_URL", "http://localhost:3000").rstrip("/")
GRAFANA_USER = os.environ.get("GRAFANA_USER", "admin")
GRAFANA_PASS = os.environ.get("GRAFANA_PASS", "admin")

# node-exporter nur strikt pruefen, wenn explizit gefordert.
STRICT_NODE_EXPORTER = os.environ.get("STRICT_NODE_EXPORTER", "false").lower() == "true"
# telemetrygen-Pipeline-Test standardmaessig aktiv.
RUN_TELEMETRYGEN = os.environ.get("RUN_TELEMETRYGEN", "true").lower() == "true"

SERVICE_NAME = "food-order-backend"
HTTP_TIMEOUT = 10


# --- URL-Konstanten fuer die Testmodule -------------------------------------
@pytest.fixture(scope="session")
def urls():
    return {
        "backend": BACKEND_URL,
        "prom": PROM_URL,
        "tempo": TEMPO_URL,
        "loki": LOKI_URL,
        "grafana": GRAFANA_URL,
    }


@pytest.fixture(scope="session")
def grafana_auth():
    return (GRAFANA_USER, GRAFANA_PASS)


@pytest.fixture(scope="session")
def cfg():
    return {
        "strict_node_exporter": STRICT_NODE_EXPORTER,
        "run_telemetrygen": RUN_TELEMETRYGEN,
        "service_name": SERVICE_NAME,
    }


# --- Geteilte HTTP-Session als Fixture (fuer direkte Aufrufe in den Tests) ---
@pytest.fixture(scope="session")
def http():
    """Geteilte requests.Session (Keep-Alive + Retry); am Ende geschlossen."""
    yield SESSION
    SESSION.close()


# --- until(): pollt bis fn ein "truthy"/nicht-leeres Ergebnis liefert --------
@pytest.fixture(scope="session")
def until():
    def _until(fn, timeout=30, interval=3, what="Bedingung"):
        """Ruft fn() wiederholt auf, bis das Ergebnis truthy ist; gibt es zurueck.

        Wirft AssertionError nach `timeout` Sekunden. Exceptions in fn werden als
        "noch nicht bereit" gewertet und wiederholt.
        """
        deadline = time.time() + timeout
        last_err = None
        while time.time() < deadline:
            try:
                result = fn()
                if result:
                    return result
            except Exception as exc:  # noqa: BLE001 – bewusst tolerant beim Pollen
                last_err = exc
            time.sleep(interval)
        raise AssertionError(
            f"Timeout ({timeout}s) beim Warten auf: {what}"
            + (f" (letzter Fehler: {last_err})" if last_err else "")
        )

    return _until


# --- Prometheus-Textparser-Helfer -------------------------------------------
def _parse_prometheus_text(text):
    """Extrahiert die Serien-Namen (ohne Labels) aus dem Prometheus-Textformat.
    Rueckgabe: set(serien_ohne_labels).
    """
    names = set()
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        m = re.match(r"^([a-zA-Z_:][a-zA-Z0-9_:]*)", line)
        if m:
            names.add(m.group(1))
    return names


def _fetch_actuator_prometheus():
    """Holt den aktuellen /actuator/prometheus-Text (ein gemeinsamer Fetch)."""
    r = SESSION.get(f"{BACKEND_URL}/actuator/prometheus", timeout=HTTP_TIMEOUT)
    r.raise_for_status()
    return r.text


@pytest.fixture(scope="session")
def prom_text():
    """Liefert eine Funktion, die den aktuellen /actuator/prometheus-Text holt."""
    return _fetch_actuator_prometheus


@pytest.fixture(scope="session")
def prom_series():
    """Set aller aktuell exponierten Serien-Namen vom Actuator-Endpoint."""
    def _get():
        text = _fetch_actuator_prometheus()
        return _parse_prometheus_text(text), text
    return _get


# --- Readiness-Gate (wartet, bis alle Backends erreichbar sind) -------------
@pytest.fixture(scope="session", autouse=True)
def readiness():
    checks = [
        ("Backend readiness", f"{BACKEND_URL}/actuator/health/readiness", 200),
        ("Prometheus", f"{PROM_URL}/-/ready", 200),
        ("Tempo", f"{TEMPO_URL}/ready", 200),
        ("Loki", f"{LOKI_URL}/ready", 200),
        ("Grafana", f"{GRAFANA_URL}/api/health", 200),
    ]
    deadline = time.time() + 90
    pending = list(checks)
    last = {}
    while pending and time.time() < deadline:
        still = []
        for name, url, want in pending:
            try:
                code = SESSION.get(url, timeout=HTTP_TIMEOUT).status_code
                last[name] = code
                if code != want:
                    still.append((name, url, want))
            except Exception as exc:  # noqa: BLE001
                last[name] = f"err:{exc}"
                still.append((name, url, want))
        pending = still
        if pending:
            time.sleep(3)
    if pending:
        detail = ", ".join(f"{n}={last.get(n)}" for n, _, _ in pending)
        pytest.fail(f"Stack nicht bereit (Readiness-Gate): {detail}")
    return True


# --- run_id: eindeutiger Marker fuer diese Testsession ----------------------
@pytest.fixture(scope="session")
def run_id():
    return f"{int(time.time())}-{uuid.uuid4().hex[:6]}"


# --- traffic: erzeugt einmalig deterministische Last ------------------------
@pytest.fixture(scope="session")
def traffic(run_id, until):
    """Setzt einmalig Last ab und gibt Kontext zurueck.

    - prueft, dass der Produktkatalog nicht leer ist (sonst "DB leer")
    - 2 gueltige Bestellungen mit eindeutigem customerName
    - 1 ungueltige Bestellung (productId 99999 -> 404)
    - ein paar GETs
    """
    customer = f"obs-ci-{run_id}"

    # Produktkatalog muss befuellt sein.
    products = until(
        lambda: SESSION.get(f"{BACKEND_URL}/api/products", timeout=HTTP_TIMEOUT).json(),
        timeout=30, what="GET /api/products liefert Produkte",
    )
    assert isinstance(products, list) and len(products) >= 1, "DB leer: keine Produkte"

    valid_orders = 0
    for _ in range(2):
        resp = SESSION.post(
            f"{BACKEND_URL}/api/orders",
            json={"customerName": customer, "items": [{"productId": 1, "quantity": 2}]},
            timeout=HTTP_TIMEOUT,
        )
        assert resp.status_code == 201, f"gueltige Bestellung erwartet 201, war {resp.status_code}"
        valid_orders += 1

    # Ungueltige Bestellung: erwartet 404 (Produkt existiert nicht).
    bad = SESSION.post(
        f"{BACKEND_URL}/api/orders",
        json={"customerName": customer, "items": [{"productId": 99999, "quantity": 1}]},
        timeout=HTTP_TIMEOUT,
    )
    assert bad.status_code == 404, f"ungueltige Bestellung erwartet 404, war {bad.status_code}"

    # Ein paar Lese-Requests fuer HTTP-/Trace-Volumen.
    for _ in range(2):
        SESSION.get(f"{BACKEND_URL}/api/products", timeout=HTTP_TIMEOUT)
    SESSION.get(f"{BACKEND_URL}/api/products/1", timeout=HTTP_TIMEOUT)

    return {
        "customer": customer,
        "run_id": run_id,
        "valid_orders": valid_orders,
        "products": products,
    }


# --- Loki-Query-Helfer (query_range mit Nanosekunden-Fenster) ---------------
@pytest.fixture(scope="session")
def loki_query_range():
    def _q(query, minutes_back=15, minutes_fwd=1, limit=10, direction="backward"):
        now = time.time()
        start = int((now - minutes_back * 60) * 1e9)
        end = int((now + minutes_fwd * 60) * 1e9)
        r = SESSION.get(
            f"{LOKI_URL}/loki/api/v1/query_range",
            params={
                "query": query,
                "start": str(start),
                "end": str(end),
                "limit": str(limit),
                "direction": direction,
            },
            timeout=HTTP_TIMEOUT,
        )
        r.raise_for_status()
        return r.json()["data"]["result"]
    return _q


# --- Tempo-Search-Helfer -----------------------------------------------------
@pytest.fixture(scope="session")
def tempo_search():
    def _s(traceql, limit=5, seconds_back=900, seconds_fwd=5):
        # Explizites Zeitfenster: ohne start/end liefert Tempo aeltere,
        # gecachte Ergebnisse und nicht zuverlaessig die frischesten Traces.
        now = int(time.time())
        r = SESSION.get(
            f"{TEMPO_URL}/api/search",
            params={
                "q": traceql,
                "limit": str(limit),
                "start": str(now - seconds_back),
                "end": str(now + seconds_fwd),
            },
            timeout=HTTP_TIMEOUT,
        )
        r.raise_for_status()
        return r.json().get("traces", []) or []
    return _s


# --- Bestell-Helfer: gibt eine Funktion zum Absetzen gueltiger Bestellungen --
@pytest.fixture(scope="session")
def place_orders():
    def _place(customer, count=1, product_id=1, quantity=2):
        placed = 0
        for _ in range(count):
            resp = SESSION.post(
                f"{BACKEND_URL}/api/orders",
                json={
                    "customerName": customer,
                    "items": [{"productId": product_id, "quantity": quantity}],
                },
                timeout=HTTP_TIMEOUT,
            )
            assert resp.status_code == 201, (
                f"Bestellung erwartet 201, war {resp.status_code}"
            )
            placed += 1
        return placed
    return _place


# --- PromQL-Helfer: rechnende Queries gegen Prometheus ----------------------
def _to_float(raw):
    """Parst einen Prometheus-Sample-Wert robust (inkl. NaN/Inf)."""
    s = str(raw)
    low = s.lower()
    if low in ("nan",):
        return float("nan")
    if low in ("+inf", "inf"):
        return float("inf")
    if low == "-inf":
        return float("-inf")
    return float(s)


@pytest.fixture(scope="session")
def promql():
    """Fixture mit `instant(query)` und `instant_sum(query)`.

    - instant(query): bei resultType 'vector' -> Liste von (labels_dict, float);
      bei 'scalar' -> ein einzelner float. Wirft bei status != 'success'.
    - instant_sum(query): Summe aller Vektor-Werte (NaN werden ignoriert);
      praktisch, wenn eine Serie mehrfach (mehrere Instanzen) auftritt.
    """
    def instant(query):
        r = SESSION.get(
            f"{PROM_URL}/api/v1/query", params={"query": query}, timeout=HTTP_TIMEOUT
        )
        r.raise_for_status()
        body = r.json()
        if body.get("status") != "success":
            raise AssertionError(f"PromQL status != success: {body}")
        data = body["data"]
        rtype = data["resultType"]
        if rtype == "scalar":
            return _to_float(data["result"][1])
        if rtype == "vector":
            return [(s["metric"], _to_float(s["value"][1])) for s in data["result"]]
        raise AssertionError(f"unerwarteter resultType: {rtype}")

    def instant_sum(query):
        res = instant(query)
        if isinstance(res, float):
            return res
        total = 0.0
        for _labels, val in res:
            if not math.isnan(val):  # NaN aussortieren
                total += val
        return total

    return types.SimpleNamespace(instant=instant, instant_sum=instant_sum)

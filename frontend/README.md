# Food-Order Frontend (Angular 22)

Bestell-UI der OpenTelemetry-Demo: Produktliste anzeigen, Warenkorb verwalten,
Bestellung an das Spring-Boot-Backend senden. Standalone Components, signal-first,
zoneless Change Detection, neue Control-Flow-Syntax.

## Voraussetzungen

- Node 24 (LTS), npm

## Lokale Entwicklung

```bash
npm install
npm start        # ng serve auf http://localhost:4200
```

Der Dev-Server proxyt `/api` via `proxy.conf.json` an `http://localhost:8081`
(lokal laufendes Backend). Im Container uebernimmt nginx diese Rolle.

## Production-Build

```bash
npm run build
```

Output-Verzeichnis (Angular Application Builder):
`dist/food-order-frontend/browser` — genau dieser Ordner wird ins nginx-Image kopiert.

## Docker

```bash
docker build -t food-order-frontend .
```

Multi-Stage: `node:24-alpine` (Build) -> `nginx:alpine` (Runtime, Port 80).
nginx liefert die SPA aus (Fallback auf `index.html`) und proxyt `/api/` an
`http://backend:8081` (Compose-Service-Name). Im Compose wird `8082:80` gemappt.

## API-Vertraege

- `GET /api/products` -> `[{ id, name, description, priceCents, category }]`
- `POST /api/orders` Body `{ customerName, items: [{ productId, quantity }] }`
  -> `{ id, status, totalCents, createdAt, items: [...] }`

Preise kommen als Cent-Integer und werden im UI via `EuroPipe` als EUR formatiert.

## Struktur

- `src/app/services/` — `ProductService`, `OrderService` (HttpClient, relative `/api`-URLs),
  `CartService` (signal-basierter Warenkorb-State)
- `src/app/components/` — `product-list`, `cart`, `order-confirmation` (Praesentation)
- `src/app/app.ts` — Container: Laden/Fehler/Bestellablauf
- `src/app/pipes/euro.pipe.ts` — Cent -> EUR

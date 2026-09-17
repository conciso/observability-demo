# --- Build-Stage: Angular-App mit Node 24 bauen ---
FROM node:24-alpine AS build
WORKDIR /app

# Nur Manifeste kopieren -> reproduzierbare, cache-freundliche Installation
COPY package.json package-lock.json ./
RUN npm ci

# Quellen kopieren und Production-Build erzeugen
COPY . .
RUN npm run build

# --- Runtime-Stage: statische Artefakte via nginx ausliefern ---
FROM nginx:alpine AS runtime

# Eigene nginx-Konfiguration (SPA-Fallback + /api-Proxy auf backend:8081)
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Angular-Application-Builder legt die Browser-Artefakte unter dist/<projekt>/browser ab
COPY --from=build /app/dist/food-order-frontend/browser /usr/share/nginx/html

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]

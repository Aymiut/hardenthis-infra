#!/bin/bash
set -euo pipefail

# --- Install Traefik ---
TRAEFIK_VERSION="3.3.3"
curl -sL "https://github.com/traefik/traefik/releases/download/v$${TRAEFIK_VERSION}/traefik_v$${TRAEFIK_VERSION}_linux_amd64.tar.gz" \
  | tar xz -C /usr/local/bin traefik
chmod +x /usr/local/bin/traefik

# --- Directories ---
mkdir -p /etc/traefik

# --- Static config (Traefik) ---
cat > /etc/traefik/traefik.yml << 'TRAEFIKYML'
entryPoints:
  web:
    address: ":80"

providers:
  # Routes dynamiques pour les labs (écrites par le backend dans Redis)
  redis:
    endpoints:
      - "${redis_endpoint}:6379"
    password: "${redis_auth_token}"
    tls:
      insecureSkipVerify: false
  # Routes statiques pour backend/frontend
  file:
    filename: /etc/traefik/routes.yml

ping:
  entryPoint: web

log:
  level: INFO

api:
  dashboard: false
TRAEFIKYML

# --- Static routes (file provider) ---
cat > /etc/traefik/routes.yml << 'ROUTESYML'
http:
  routers:
    frontend:
      rule: "Host(`${domain_name}`)"
      service: frontend-svc
      entryPoints:
        - web
    api:
      rule: "Host(`api.${domain_name}`)"
      service: api-svc
      entryPoints:
        - web

  services:
    frontend-svc:
      loadBalancer:
        servers:
          - url: "http://frontend.${internal_namespace}:3001"
    api-svc:
      loadBalancer:
        servers:
          - url: "http://backend.${internal_namespace}:3000"
ROUTESYML

# --- Systemd service ---
cat > /etc/systemd/system/traefik.service << 'SYSTEMD'
[Unit]
Description=Traefik Reverse Proxy
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/traefik --configFile=/etc/traefik/traefik.yml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SYSTEMD

systemctl daemon-reload
systemctl enable traefik
systemctl start traefik

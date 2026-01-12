#!/bin/bash
set -e

echo "Setting up nginx configuration..."
mkdir -p nginx/certs

# Create nginx config if it doesn't exist
if [ ! -f nginx/default.conf.template ]; then
  cat > nginx/default.conf.template << 'NGINX_EOF'
server {
    listen 80;
    listen [::]:80;
    server_name _;
    server_tokens off;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name _;
    server_tokens off;

    ssl_certificate /certs/wildcard.crt;
    ssl_certificate_key /certs/wildcard.key;

    access_log off;
    autoindex off;

    include mime.types;
    types {
        application/manifest+json webmanifest;
    }

    sendfile on;
    root /usr/share/nginx/html;

    location ~ ^/api/eda/ {
        proxy_pass http://eda-api:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
    }

    location ~ /api/eda/ws/[0-9a-z-]+ {
        proxy_pass http://eda-api:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location / {
        autoindex off;
        expires off;
        add_header Cache-Control "public, max-age=0, s-maxage=0, must-revalidate" always;
        try_files $uri /index.html =404;
    }
}
NGINX_EOF
  echo "Created nginx configuration"
fi

# Download SSL certs if they don't exist
if [ ! -f nginx/certs/wildcard.crt ]; then
  echo "Downloading SSL certificates..."
  curl -s https://raw.githubusercontent.com/ansible/eda-server/main/tools/docker/nginx/certs/wildcard.crt -o nginx/certs/wildcard.crt
  curl -s https://raw.githubusercontent.com/ansible/eda-server/main/tools/docker/nginx/certs/wildcard.key -o nginx/certs/wildcard.key
  echo "SSL certificates downloaded"
fi

echo "Nginx setup complete"

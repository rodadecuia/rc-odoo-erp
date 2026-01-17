#!/bin/bash
# Script para corrigir o Nginx preso em modo de validação

DOMAIN="erp.rodadecuia.com.br"

echo "Restaurando configuração do Nginx..."

# Verifica se o certificado existe
if [ -f "../certbot/conf/live/$DOMAIN/fullchain.pem" ]; then
    echo "Certificado encontrado! Configurando HTTPS..."
    cat > ../nginx/nginx.conf <<EOF
upstream odoo { server web:8069; }
upstream odoochat { server web:8072; }

server {
    listen 80;
    server_name $DOMAIN;
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 https://\$host\$request_uri; }
}

server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    proxy_read_timeout 720s;
    proxy_connect_timeout 720s;
    proxy_send_timeout 720s;

    location / {
        proxy_pass http://odoo;
        proxy_redirect off;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /longpolling { proxy_pass http://odoochat; }
}
EOF
else
    echo "Certificado NÃO encontrado. Configurando HTTP (Porta 80)..."
    cat > ../nginx/nginx.conf <<EOF
upstream odoo { server web:8069; }
upstream odoochat { server web:8072; }

server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://odoo;
        proxy_redirect off;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /longpolling {
        proxy_pass http://odoochat;
    }
}
EOF
fi

echo "Reiniciando Nginx..."
cd ..
docker compose restart nginx
echo "Concluído!"

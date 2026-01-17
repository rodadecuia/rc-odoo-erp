#!/bin/bash

# Script de Instalação e Atualização Automática do RC ODOO ERP
# Suporta: Debian/Ubuntu e RHEL/Rocky/CentOS

set -e

TARGET_DIR="/home/rc-odoo-erp"
REPO_URL="https://github.com/rodadecuia/rc-odoo-erp.git"

# Verifica se é root
if [ "$EUID" -ne 0 ]; then
  echo "ERRO: Por favor, execute como root."
  exit 1
fi

# Detecta o Sistema Operacional
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    LIKE=$ID_LIKE
else
    echo "ERRO: Não foi possível detectar o sistema operacional."
    exit 1
fi

echo ">> Sistema detectado: $OS ($LIKE)"

# --- FUNÇÕES ---

install_docker() {
    if command -v docker &> /dev/null; then
        echo ">> Docker já está instalado."
        return
    fi

    echo ">> Instalando Docker..."
    if [[ "$OS" == "debian" || "$OS" == "ubuntu" || "$LIKE" == *"debian"* ]]; then
        apt-get update
        apt-get install -y ca-certificates curl gnupg git
        install -m 0755 -d /etc/apt/keyrings
        if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
            curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            chmod a+r /etc/apt/keyrings/docker.gpg
        fi
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    elif [[ "$OS" == "rocky" || "$OS" == "centos" || "$OS" == "rhel" || "$LIKE" == *"rhel"* || "$LIKE" == *"fedora"* ]]; then
        dnf install -y yum-utils git
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        systemctl start docker
        systemctl enable docker
    else
        echo "ERRO: Distro não suportada automaticamente."
        exit 1
    fi
}

update_system() {
    echo ""
    echo "================================================================"
    echo " ATUALIZAÇÃO DO SISTEMA DETECTADA"
    echo "================================================================"
    echo ">> Diretório $TARGET_DIR encontrado."

    cd "$TARGET_DIR"

    echo ">> Salvando alterações locais (stash)..."
    # Salva configs locais (ex: nginx.conf com SSL) para não perder no pull
    git stash

    echo ">> Atualizando código fonte (git pull)..."
    git pull origin main || git pull origin master

    echo ">> Restaurando alterações locais..."
    # Tenta restaurar. Se falhar (conflito), mantém o que veio do git e avisa.
    git stash pop || echo "AVISO: Conflito ao restaurar stash ou nada para restaurar. Verifique nginx/nginx.conf."

    # Garante que o ajuste de produção no docker-compose.yml seja aplicado novamente
    if [ -f "docker-compose.yml" ]; then
        echo ">> Reaplicando ajustes de produção..."
        sed -i '/oca_addons/d' docker-compose.yml
    fi

    echo ">> Baixando novas imagens Docker..."
    docker compose pull

    echo ">> Reiniciando serviços..."
    docker compose up -d --remove-orphans

    echo ">> Limpando imagens antigas..."
    docker image prune -f

    echo ""
    echo ">> Atualização concluída com sucesso!"
    docker compose ps
    exit 0
}

# --- FLUXO PRINCIPAL ---

install_docker

# Verifica se é uma atualização
if [ -d "$TARGET_DIR" ] && [ -d "$TARGET_DIR/.git" ]; then
    read -p "O sistema já está instalado em $TARGET_DIR. Deseja atualizar? (s/n): " DO_UPDATE
    if [[ "$DO_UPDATE" =~ ^[Ss]$ ]]; then
        update_system
    else
        echo ">> Para realizar uma instalação limpa, remova o diretório $TARGET_DIR manualmente ou escolha um novo local."
        echo ">> Exemplo: rm -rf $TARGET_DIR"
        exit 0
    fi
fi

# --- INSTALAÇÃO LIMPA ---

echo ">> Iniciando Instalação Limpa em $TARGET_DIR..."

if [ -d "$TARGET_DIR" ]; then
    echo ">> O diretório existe mas não parece um repositório git válido ou o usuário optou por não atualizar."
    echo ">> Fazendo backup para ${TARGET_DIR}_backup_$(date +%s)..."
    mv "$TARGET_DIR" "${TARGET_DIR}_backup_$(date +%s)"
fi

mkdir -p "$TARGET_DIR"
cd "$TARGET_DIR"

# Git Sparse Checkout
git init
git remote add origin "$REPO_URL"
git config core.sparseCheckout true

echo "nginx/" >> .git/info/sparse-checkout
echo "odoo_server/addons/" >> .git/info/sparse-checkout
echo "odoo_server/config/" >> .git/info/sparse-checkout
echo "scripts/" >> .git/info/sparse-checkout
echo "docker-compose.yml" >> .git/info/sparse-checkout
echo ".env.example" >> .git/info/sparse-checkout

echo ">> Baixando arquivos..."
git pull origin main || git pull origin master

# Limpeza
rm -f nginx/Dockerfile

# Ajuste Produção
if [ -f "docker-compose.yml" ]; then
    sed -i '/oca_addons/d' docker-compose.yml
fi

# .env
if [ -f ".env.example" ]; then
    cp .env.example .env
fi

mkdir -p odoo_server/addons
mkdir -p certbot/conf
mkdir -p certbot/www

# Configuração SSL Interativa
echo ""
echo "----------------------------------------------------------------"
echo "Configuração de Domínio e SSL (Opcional)"
echo "----------------------------------------------------------------"
read -p "Deseja configurar um domínio e SSL agora? (s/n): " CONFIGURE_SSL

if [[ "$CONFIGURE_SSL" =~ ^[Ss]$ ]]; then
    read -p "Digite o domínio principal (ex: odoo.minhaempresa.com): " DOMAIN
    read -p "Digite o email para o Certbot: " EMAIL

    if [ -n "$DOMAIN" ] && [ -n "$EMAIL" ]; then
        echo ">> Configurando Nginx para validação SSL..."

        cat > nginx/nginx.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 200 'Validando SSL...'; add_header Content-Type text/plain; }
}
EOF

        echo ">> Baixando imagens..."
        docker compose pull

        echo ">> Iniciando Nginx..."
        docker compose up -d nginx
        sleep 5

        echo ">> Solicitando certificado..."
        docker compose run --rm certbot certonly --webroot --webroot-path /var/www/certbot --email "$EMAIL" -d "$DOMAIN" --agree-tos --force-renewal

        if [ -f "certbot/conf/live/$DOMAIN/fullchain.pem" ]; then
            echo ">> Certificado OK! Configurando HTTPS..."

            cat > nginx/nginx.conf <<EOF
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
            docker compose down
        else
            echo "ERRO: Falha no SSL. Configurando HTTP básico."
            cat > nginx/nginx.conf <<EOF
upstream odoo { server web:8069; }
upstream odoochat { server web:8072; }
server {
    listen 80;
    server_name $DOMAIN;
    location / { proxy_pass http://odoo; }
    location /longpolling { proxy_pass http://odoochat; }
}
EOF
        fi
    fi
fi

echo ""
echo ">> Iniciando serviços..."
docker compose up -d
echo ">> Instalação Concluída!"
docker compose ps

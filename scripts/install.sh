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

# Função inteligente para configurar o Nginx baseado no estado atual dos certificados
finalize_nginx_config() {
    echo ">> Verificando configuração final do Nginx..."

    # Tenta detectar domínio existente nos certificados
    DETECTED_DOMAIN=""
    if [ -d "certbot/conf/live" ]; then
        # Pega o primeiro diretório que não seja README
        DETECTED_DOMAIN=$(ls -F certbot/conf/live/ | grep / | head -n 1 | tr -d /)
    fi

    if [ -n "$DETECTED_DOMAIN" ] && [ -f "certbot/conf/live/$DETECTED_DOMAIN/fullchain.pem" ]; then
        echo ">> Certificado SSL detectado para $DETECTED_DOMAIN. Aplicando template HTTPS..."

        # Garante que estamos usando o template limpo do repositório
        # Isso remove qualquer configuração anterior ou conflito de merge
        if [ -f "nginx/nginx.conf" ]; then
             git checkout nginx/nginx.conf 2>/dev/null || true
        fi

        # Substitui o placeholder pelo domínio real
        sed -i "s/__DOMAIN__/$DETECTED_DOMAIN/g" nginx/nginx.conf

    else
        echo ">> Nenhum certificado SSL válido encontrado."

        # Verifica se o Nginx está preso no modo de validação ou se não existe config
        if grep -q "Validando SSL" nginx/nginx.conf 2>/dev/null || [ ! -f "nginx/nginx.conf" ]; then
            echo ">> Nginx está em modo de validação ou sem config. Revertendo para HTTP padrão..."

            # Gera config HTTP básica de fallback
            cat > nginx/nginx.conf <<EOF
upstream odoo { server web:8069; }
upstream odoochat { server web:8072; }

map \$http_upgrade \$connection_upgrade {
  default upgrade;
  ''      close;
}

server {
    listen 80;
    server_name _;

    client_max_body_size 100M;
    proxy_read_timeout 720s;
    proxy_connect_timeout 720s;
    proxy_send_timeout 720s;

    proxy_set_header X-Forwarded-Host \$http_host;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Real-IP \$remote_addr;

    location /websocket {
        proxy_pass http://odoochat;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
    }

    location / {
        proxy_pass http://odoo;
        proxy_redirect off;
    }

    location ~* /web/static/ {
        proxy_cache_valid 200 90m;
        proxy_buffering on;
        expires 864000;
        proxy_pass http://odoo;
    }
}
EOF
        else
            echo ">> Mantendo configuração HTTP existente."
        fi
    fi
}

update_system() {
    echo ""
    echo "================================================================"
    echo " ATUALIZAÇÃO DO SISTEMA DETECTADA"
    echo "================================================================"
    echo ">> Diretório $TARGET_DIR encontrado."

    cd "$TARGET_DIR"

    # 1. Backup de segurança de configs locais críticas
    echo ">> Fazendo backup de configurações locais..."
    if [ -f "nginx/nginx.conf" ]; then
        cp nginx/nginx.conf nginx/nginx.conf.bak_$(date +%s)
    fi

    # 2. Reseta arquivos gerenciados pelo script para evitar conflitos de merge
    echo ">> Resetando arquivos de configuração gerenciados..."
    git checkout nginx/nginx.conf 2>/dev/null || true

    # 3. Salva outras alterações do usuário (ex: .env)
    echo ">> Salvando alterações do usuário (stash)..."
    git stash

    # 4. Atualiza o repositório
    echo ">> Atualizando código fonte (git pull)..."
    git pull origin main || git pull origin master

    # 5. Restaura alterações do usuário
    echo ">> Restaurando alterações do usuário..."
    git stash pop || echo "AVISO: Nada para restaurar ou conflito detectado no stash pop."

    # 6. Garante novamente que o template do nginx é o novo (caso o stash pop tenha trazido o velho)
    git checkout nginx/nginx.conf 2>/dev/null || true

    # 7. Ajustes de produção
    if [ -f "docker-compose.yml" ]; then
        echo ">> Reaplicando ajustes de produção..."
        sed -i '/oca_addons/d' docker-compose.yml
    fi

    echo ">> Baixando novas imagens Docker..."
    docker compose pull

    # 8. Regenera a configuração final baseada no novo template
    finalize_nginx_config

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

        echo ">> Iniciando Nginx (modo isolado)..."
        docker compose up -d --no-deps nginx
        sleep 5

        echo ">> Solicitando certificado..."

        # Usa docker run para evitar problemas de entrypoint
        docker run --rm \
            -v "$(pwd)/certbot/conf:/etc/letsencrypt" \
            -v "$(pwd)/certbot/www:/var/www/certbot" \
            certbot/certbot \
            certonly --webroot --webroot-path /var/www/certbot \
            --email "$EMAIL" -d "$DOMAIN" --agree-tos --force-renewal

        # Para o nginx temporário
        docker compose stop nginx
    fi
fi

# Chama a função inteligente para gerar a config final (HTTPS ou HTTP)
finalize_nginx_config

echo ""
echo ">> Iniciando serviços..."
docker compose up -d

echo ">> Limpando imagens antigas..."
docker image prune -f

echo ">> Instalação Concluída!"
docker compose ps

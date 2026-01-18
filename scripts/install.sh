#!/bin/bash

# Script de Instalação e Atualização Automática do RC ODOO ERP
# Suporta: Debian/Ubuntu e RHEL/Rocky/CentOS
# Uso: ./install.sh [DOMINIO] [EMAIL]
# Exemplo: ./install.sh odoo.minhaempresa.com admin@minhaempresa.com

set -e

TARGET_DIR="/home/rc-odoo-erp"
REPO_URL="https://github.com/rodadecuia/rc-odoo-erp.git"

# Argumentos Opcionais para Instalação Não-Interativa
ARG_DOMAIN="$1"
ARG_EMAIL="$2"

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

# Função para gerar e configurar a senha mestra
setup_master_password() {
    if [ -f ".env" ]; then
        # Verifica se ODOO_MASTER_PASSWORD já existe e não é 'admin' (padrão do exemplo)
        CURRENT_PASS=$(grep "^ODOO_MASTER_PASSWORD=" .env | cut -d '=' -f2)

        if [ -z "$CURRENT_PASS" ] || [ "$CURRENT_PASS" == "admin" ]; then
            echo ">> Gerando nova senha mestra segura..."
            # Gera uma senha aleatória de 16 caracteres
            NEW_PASS=$(openssl rand -base64 12)

            if grep -q "^ODOO_MASTER_PASSWORD=" .env; then
                # Substitui se já existir a linha
                sed -i "s|^ODOO_MASTER_PASSWORD=.*|ODOO_MASTER_PASSWORD=$NEW_PASS|" .env
            else
                # Adiciona se não existir
                echo "ODOO_MASTER_PASSWORD=$NEW_PASS" >> .env
            fi
            echo ">> Senha mestra configurada."
        fi
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

        if [ -f "nginx/nginx.conf" ]; then
             git checkout nginx/nginx.conf 2>/dev/null || true
        fi

        # Substitui o placeholder pelo domínio real
        sed -i "s/__DOMAIN__/$DETECTED_DOMAIN/g" nginx/nginx.conf

        # Verificação de segurança
        if grep -q "__DOMAIN__" nginx/nginx.conf; then
            echo "ERRO: Falha na substituição do domínio no nginx.conf. Revertendo para HTTP."
            FORCE_HTTP=true
        fi
    else
        echo ">> Nenhum certificado SSL válido encontrado."
        FORCE_HTTP=true
    fi

    if [ "$FORCE_HTTP" = true ]; then
        echo ">> Configurando Nginx em modo HTTP (Fallback)..."

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
    fi
}

show_final_info() {
    echo ""
    echo "================================================================"
    echo " INSTALAÇÃO CONCLUÍDA COM SUCESSO!"
    echo "================================================================"
    echo ""
    echo ">> Status dos Serviços:"
    docker compose ps
    echo ""

    if [ -f ".env" ]; then
        MASTER_PASS=$(grep "^ODOO_MASTER_PASSWORD=" .env | cut -d '=' -f2)
        echo ">> CREDENCIAIS IMPORTANTES (Salve agora!):"
        echo "   Senha Mestra do Odoo: $MASTER_PASS"
        echo "   (Usada para criar/gerenciar bancos de dados)"
        echo ""
    fi

    echo ">> Acesse seu sistema em:"
    if [ -n "$DETECTED_DOMAIN" ]; then
        echo "   https://$DETECTED_DOMAIN"
    else
        echo "   http://SEU_IP_OU_DOMINIO"
    fi
    echo "================================================================"
}

update_system() {
    echo ""
    echo "================================================================"
    echo " ATUALIZAÇÃO AUTOMÁTICA INICIADA"
    echo "================================================================"
    echo ">> Diretório $TARGET_DIR encontrado."

    cd "$TARGET_DIR"

    # --- CORREÇÃO DE ESTADO GIT ---
    rm -f .git/index.lock
    if [ -f ".git/MERGE_HEAD" ]; then
        git merge --abort 2>/dev/null || true
    fi
    git checkout -f nginx/nginx.conf 2>/dev/null || true
    git reset HEAD nginx/nginx.conf 2>/dev/null || true
    # ------------------------------

    echo ">> Fazendo backup de configurações locais..."
    if [ -f "nginx/nginx.conf" ]; then
        cp nginx/nginx.conf nginx/nginx.conf.bak_$(date +%s)
    fi

    echo ">> Resetando arquivos de configuração gerenciados..."
    git checkout nginx/nginx.conf 2>/dev/null || true

    echo ">> Salvando alterações do usuário (stash)..."
    git stash

    echo ">> Atualizando código fonte (git pull)..."
    git pull origin main || git pull origin master

    echo ">> Restaurando alterações do usuário..."
    git stash pop || echo "AVISO: Nada para restaurar ou conflito detectado no stash pop."

    git checkout nginx/nginx.conf 2>/dev/null || true

    if [ -f "docker-compose.yml" ]; then
        echo ">> Reaplicando ajustes de produção..."
        sed -i '/oca_addons/d' docker-compose.yml
    fi

    # Garante senha mestra
    setup_master_password

    echo ">> Baixando novas imagens Docker..."
    docker compose pull

    finalize_nginx_config

    echo ">> Reiniciando serviços..."
    docker compose up -d --remove-orphans

    echo ">> Limpando imagens antigas..."
    docker image prune -f

    show_final_info
    exit 0
}

# --- FLUXO PRINCIPAL ---

install_docker

# Verifica se é uma atualização (AUTOMÁTICA SE EXISTIR)
if [ -d "$TARGET_DIR" ] && [ -d "$TARGET_DIR/.git" ]; then
    update_system
fi

# --- INSTALAÇÃO LIMPA ---

echo ">> Iniciando Instalação Limpa em $TARGET_DIR..."

if [ -d "$TARGET_DIR" ]; then
    echo ">> O diretório existe mas não parece um repositório git válido."
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

# Gera senha mestra
setup_master_password

# Configuração SSL (Interativa ou via Argumentos)
CONFIGURE_SSL="n"
DOMAIN=""
EMAIL=""

if [ -n "$ARG_DOMAIN" ] && [ -n "$ARG_EMAIL" ]; then
    echo ">> Argumentos de domínio detectados: $ARG_DOMAIN"
    CONFIGURE_SSL="s"
    DOMAIN="$ARG_DOMAIN"
    EMAIL="$ARG_EMAIL"
else
    echo ""
    echo "----------------------------------------------------------------"
    echo "Configuração de Domínio e SSL (Opcional)"
    echo "----------------------------------------------------------------"
    read -p "Deseja configurar um domínio e SSL agora? (s/n): " CONFIGURE_SSL
    if [[ "$CONFIGURE_SSL" =~ ^[Ss]$ ]]; then
        read -p "Digite o domínio principal (ex: odoo.minhaempresa.com): " DOMAIN
        read -p "Digite o email para o Certbot: " EMAIL
    fi
fi

if [[ "$CONFIGURE_SSL" =~ ^[Ss]$ ]] && [ -n "$DOMAIN" ] && [ -n "$EMAIL" ]; then
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

    docker run --rm \
        -v "$(pwd)/certbot/conf:/etc/letsencrypt" \
        -v "$(pwd)/certbot/www:/var/www/certbot" \
        certbot/certbot \
        certonly --webroot --webroot-path /var/www/certbot \
        --email "$EMAIL" -d "$DOMAIN" --agree-tos --force-renewal

    docker compose stop nginx
fi

finalize_nginx_config

echo ""
echo ">> Iniciando serviços..."
docker compose up -d

echo ">> Limpando imagens antigas..."
docker image prune -f

show_final_info

#!/bin/bash

# Script de Instalação Automática do RC ODOO ERP
# Suporta: Debian/Ubuntu e RHEL/Rocky/CentOS
# Instala Docker, Docker Compose e clona o projeto (Sparse Checkout)

set -e

TARGET_DIR="/home/rc-odoo-erp"
REPO_URL="https://github.com/rodadecuia/rc-odoo-erp.git"

# Verifica se é root
if [ "$EUID" -ne 0 ]; then
  echo "Por favor, execute como root."
  exit 1
fi

# Detecta o Sistema Operacional
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    LIKE=$ID_LIKE
else
    echo "Não foi possível detectar o sistema operacional."
    exit 1
fi

echo "Sistema detectado: $OS ($LIKE)"

install_docker_debian() {
    echo "Instalando Docker no Debian/Ubuntu..."
    apt-get update
    apt-get install -y ca-certificates curl gnupg git

    # Adiciona a chave GPG oficial do Docker
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    # Configura o repositório
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

install_docker_ubuntu() {
    echo "Instalando Docker no Ubuntu..."
    apt-get update
    apt-get install -y ca-certificates curl gnupg git

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

install_docker_rhel() {
    echo "Instalando Docker no RHEL/Rocky/CentOS..."
    dnf install -y yum-utils git

    # Adiciona o repo oficial
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

    dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    systemctl start docker
    systemctl enable docker
}

# Executa a instalação baseada na distro
case "$OS" in
    debian)
        install_docker_debian
        ;;
    ubuntu)
        install_docker_ubuntu
        ;;
    rocky|centos|rhel|fedora)
        install_docker_rhel
        ;;
    *)
        if [[ "$LIKE" == *"debian"* ]]; then
            install_docker_debian
        elif [[ "$LIKE" == *"rhel"* || "$LIKE" == *"fedora"* ]]; then
            install_docker_rhel
        else
            echo "Sistema operacional não suportado automaticamente por este script."
            exit 1
        fi
        ;;
esac

echo "Docker instalado com sucesso!"

# Configuração do Projeto (Sparse Checkout)
echo "Configurando o projeto em $TARGET_DIR..."

# Cria o diretório se não existir
if [ -d "$TARGET_DIR" ]; then
    echo "O diretório $TARGET_DIR já existe. Fazendo backup..."
    mv "$TARGET_DIR" "${TARGET_DIR}_backup_$(date +%s)"
fi

mkdir -p "$TARGET_DIR"
cd "$TARGET_DIR"

# Inicializa git e configura sparse checkout
git init
git remote add origin "$REPO_URL"
git config core.sparseCheckout true

# Define quais arquivos/pastas baixar
echo "nginx/" >> .git/info/sparse-checkout
echo "odoo_server/addons/" >> .git/info/sparse-checkout
echo "odoo_server/config/" >> .git/info/sparse-checkout
echo "scripts/" >> .git/info/sparse-checkout
echo "docker-compose.yml" >> .git/info/sparse-checkout
echo ".env.example" >> .git/info/sparse-checkout

# Baixa o conteúdo
echo "Baixando arquivos do repositório..."
git pull origin main || git pull origin master

# Remove o Dockerfile do nginx localmente
rm -f nginx/Dockerfile

# Ajusta docker-compose.yml para remover o volume oca_addons
if [ -f "docker-compose.yml" ]; then
    echo "Ajustando docker-compose.yml para usar addons da imagem..."
    sed -i '/oca_addons/d' docker-compose.yml
fi

# Configuração final
if [ -f ".env.example" ]; then
    echo "Criando arquivo .env a partir do exemplo..."
    cp .env.example .env
fi

# Configuração Interativa de Domínio e SSL
echo ""
echo "----------------------------------------------------------------"
echo "Configuração de Domínio e SSL (Opcional)"
echo "----------------------------------------------------------------"
read -p "Deseja configurar um domínio e SSL agora? (s/n): " CONFIGURE_SSL

if [[ "$CONFIGURE_SSL" =~ ^[Ss]$ ]]; then
    read -p "Digite o domínio principal (ex: odoo.minhaempresa.com): " DOMAIN
    read -p "Digite o email para o Certbot: " EMAIL

    if [ -n "$DOMAIN" ] && [ -n "$EMAIL" ]; then
        echo "Configurando Nginx para $DOMAIN..."

        # 1. Configura Nginx apenas para HTTP inicialmente (para validação do Certbot)
        cat > nginx/nginx.conf <<EOF
upstream odoo {
    server web:8069;
}

upstream odoochat {
    server web:8072;
}

server {
    listen 80;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        proxy_pass http://odoo;
        proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
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

        echo "Iniciando Nginx para validação..."
        docker compose up -d nginx

        echo "Aguardando inicialização do Nginx..."
        sleep 10

        echo "Solicitando certificado SSL via Certbot..."
        # Adicionado --force-renewal para garantir que ele tente obter o certificado mesmo se achar que não precisa
        # E removido --no-eff-email para evitar prompts interativos se algo der errado
        docker compose run --rm certbot certonly --webroot --webroot-path /var/www/certbot --email "$EMAIL" -d "$DOMAIN" --agree-tos --force-renewal

        # Verifica se o arquivo do certificado realmente existe
        if [ -f "certbot/conf/live/$DOMAIN/fullchain.pem" ]; then
            echo "Certificado obtido com sucesso!"

            # 2. Reescreve nginx.conf com SSL ativado e redirecionamento HTTP->HTTPS
            cat > nginx/nginx.conf <<EOF
upstream odoo {
    server web:8069;
}

upstream odoochat {
    server web:8072;
}

server {
    listen 80;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    location / {
        proxy_pass http://odoo;
        proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
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
            echo "Reiniciando Nginx com SSL..."
            docker compose restart nginx
        else
            echo "ERRO: Falha ao obter certificado. O Nginx permanecerá configurado apenas em HTTP."
            echo "Verifique se o domínio $DOMAIN está apontando corretamente para o IP deste servidor."
            echo "Verifique os logs acima para mais detalhes sobre o erro do Certbot."
        fi
    else
        echo "Domínio ou email inválidos. Pulando configuração SSL."
    fi
fi

echo "----------------------------------------------------------------"
echo "Instalação concluída!"
echo "O projeto foi instalado em: $TARGET_DIR"
echo ""
echo "Próximos passos:"
echo "1. Acesse o diretório: cd $TARGET_DIR"
echo "2. Edite o arquivo .env com suas senhas: nano .env"
echo "3. Inicie o sistema completo: docker compose up -d"
echo "----------------------------------------------------------------"

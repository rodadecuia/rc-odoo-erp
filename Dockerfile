FROM odoo:18.0

USER root

# Instala dependências do sistema necessárias para o OCA Brasil
# Nota: libpq-dev foi removido para evitar conflitos de versão com o repositório do Postgres já configurado na imagem oficial
RUN apt-get update && apt-get install -y \
    build-essential \
    python3-dev \
    libssl-dev \
    libxml2-dev \
    libxslt1-dev \
    zlib1g-dev \
    libsasl2-dev \
    libldap2-dev \
    libjpeg-dev \
    libffi-dev \
    git \
    && rm -rf /var/lib/apt/lists/*

# Copia e instala dependências Python
COPY ./requirements.txt /etc/odoo/
# Adicionado --break-system-packages para permitir instalação no ambiente Python do sistema (Debian 12+)
RUN pip3 install --no-cache-dir --break-system-packages -r /etc/odoo/requirements.txt

# Copia o arquivo de configuração personalizado
COPY ./config /etc/odoo

# Copia os addons personalizados e OCA
# Nota: A pasta oca_addons deve ser populada antes do build (ex: via script setup_oca.sh no CI)
COPY ./addons /mnt/extra-addons
COPY ./oca_addons /mnt/oca-addons

# Ajusta permissões para o usuário odoo
RUN chown -R odoo /etc/odoo /mnt/extra-addons /mnt/oca-addons

USER odoo

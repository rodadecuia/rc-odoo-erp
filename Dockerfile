FROM odoo:18.0

USER root

# Instala dependências do sistema necessárias para o OCA Brasil
# Removido libpq-dev devido a conflitos de versão com o repositório do Postgres na imagem base
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
    && rm -rf /var/lib/apt/lists/*

# Copia e instala dependências Python
COPY ./requirements.txt /etc/odoo/
RUN pip3 install --no-cache-dir -r /etc/odoo/requirements.txt

# Copia o arquivo de configuração personalizado
COPY ./config /etc/odoo

# Copia os addons personalizados e OCA
COPY ./addons /mnt/extra-addons
COPY ./oca_addons /mnt/oca-addons

# Ajusta permissões para o usuário odoo
RUN chown -R odoo /etc/odoo /mnt/extra-addons /mnt/oca-addons

USER odoo

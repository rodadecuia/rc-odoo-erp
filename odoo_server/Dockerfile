FROM odoo:18.0

USER root

# Instala dependências do sistema necessárias para o OCA Brasil e fontes para relatórios
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
    fonts-dejavu-core \
    fonts-freefont-ttf \
    fonts-freefont-otf \
    fonts-noto-core \
    fonts-inconsolata \
    fontconfig \
    libxrender1 \
    xfonts-75dpi \
    xfonts-base \
    && rm -rf /var/lib/apt/lists/*

# Copia e instala dependências Python
COPY ./requirements.txt /etc/odoo/
RUN pip3 install --no-cache-dir --break-system-packages -r /etc/odoo/requirements.txt

# Copia o arquivo de configuração personalizado
COPY ./config /etc/odoo

# Copia os addons personalizados e OCA
COPY ./addons /mnt/extra-addons
COPY ./oca_addons /mnt/oca-addons

# Configura o entrypoint personalizado
COPY ./entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Ajusta permissões para o usuário odoo
# Garante que /mnt/extra-addons exista e seja do odoo
RUN mkdir -p /mnt/extra-addons \
    && chown -R odoo:odoo /etc/odoo /mnt/extra-addons /mnt/oca-addons

USER odoo

ENTRYPOINT ["/entrypoint.sh"]
CMD ["odoo"]

FROM odoo:18.0

# Copia o arquivo de configuração personalizado
COPY ./config /etc/odoo

# Copia os addons personalizados
COPY ./addons /mnt/extra-addons

# Ajusta permissões para o usuário odoo
USER root
RUN chown -R odoo /etc/odoo /mnt/extra-addons
USER odoo

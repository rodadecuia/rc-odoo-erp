#!/bin/bash
set -e

# Função para gerar o addons_path dinamicamente
generate_addons_path() {
    # Caminho padrão dos addons do Odoo (pode variar dependendo da distro base, mas geralmente é este no Debian)
    local addons_path="/usr/lib/python3/dist-packages/odoo/addons"

    # Adiciona /mnt/extra-addons apenas se existir
    if [ -d "/mnt/extra-addons" ]; then
        addons_path="$addons_path,/mnt/extra-addons"
    fi

    local base_path="/mnt/oca-addons"

    if [ -d "$base_path" ]; then
        for dir in "$base_path"/*; do
            if [ -d "$dir" ]; then
                addons_path="$addons_path,$dir"
            fi
        done
    fi

    echo "$addons_path"
}

# Se o comando for iniciar o odoo, injeta o addons_path
if [ "$1" = "odoo" ]; then
    ADDONS_PATH=$(generate_addons_path)
    echo ">> Gerando addons_path dinâmico: $ADDONS_PATH"

    exec odoo --addons-path="$ADDONS_PATH" "${@:2}"
else
    exec "$@"
fi

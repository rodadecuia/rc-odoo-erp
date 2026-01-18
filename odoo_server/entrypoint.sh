#!/bin/bash
set -e

# Função para gerar o addons_path dinamicamente
generate_addons_path() {
    # Caminho padrão dos addons do Odoo
    local addons_path="/usr/lib/python3/dist-packages/odoo/addons"

    # Verifica se /mnt/extra-addons existe e tem permissão de leitura
    if [ -d "/mnt/extra-addons" ] && [ -r "/mnt/extra-addons" ]; then
        # Opcional: Verificar se não está vazio para evitar warnings, mas o Odoo deve aceitar vazio.
        # O erro "not a valid addons directory" geralmente é permissão ou path inexistente.
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

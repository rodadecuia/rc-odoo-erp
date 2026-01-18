#!/bin/bash
set -e

# Função para gerar o addons_path dinamicamente
generate_addons_path() {
    local base_path="/mnt/oca-addons"
    local addons_path="/mnt/extra-addons"

    # Adiciona o caminho base do Odoo se necessário (geralmente já incluído pelo Odoo, mas garantimos os extras)
    # O Odoo oficial já inclui os addons padrão. Nós só precisamos adicionar os nossos.

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

    # Se já existe um arquivo de configuração, vamos tentar adicionar ou substituir o addons_path
    # Mas a maneira mais segura e compatível com a imagem oficial é passar como argumento de linha de comando
    # que tem precedência sobre o arquivo de configuração.

    exec odoo --addons-path="$ADDONS_PATH" "${@:2}"
else
    exec "$@"
fi

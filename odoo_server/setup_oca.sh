#!/bin/bash

TARGET_DIR="oca_addons"
LIST_FILE="oca_addons_list.txt"
MODE="submodule"

if [ "$1" == "--ci" ]; then
    MODE="clone"
fi

if [ ! -f "$LIST_FILE" ]; then
    echo "Arquivo $LIST_FILE não encontrado!"
    exit 1
fi

mkdir -p $TARGET_DIR

echo "Iniciando instalação dos módulos OCA em modo: $MODE"

while IFS= read -r repo || [ -n "$repo" ]; do
    # Ignora linhas vazias ou comentários
    [[ $repo =~ ^#.*$ ]] && continue
    [ -z "$repo" ] && continue

    repo_name=$(basename "$repo" .git)
    target_path="$TARGET_DIR/$repo_name"

    if [ -d "$target_path" ]; then
        echo "Pasta $target_path já existe. Pulando."
        continue
    fi

    if [ "$MODE" == "clone" ]; then
        echo "Clonando $repo_name..."
        git clone --depth 1 -b 18.0 "$repo" "$target_path" || git clone --depth 1 "$repo" "$target_path"
    else
        echo "Adicionando submódulo $repo_name..."
        git submodule add -b 18.0 "$repo" "$target_path" || git submodule add "$repo" "$target_path"
    fi

done < "$LIST_FILE"

echo "Concluído!"

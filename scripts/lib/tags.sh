#!/usr/bin/env bash
# Lista de tags compartilhada por scripts/workstation.sh e scripts/interactive.sh (carregada com "source"). A lista
# fica em scripts/lib/tags; veja o formato no próprio arquivo.

TAG_NAMES=()
TAG_DESCS=()
TAG_ALIASES=()

# Lê o arquivo de tags nos arrays paralelos TAG_NAMES, TAG_DESCS e TAG_ALIASES (apelidos separados por espaço).
# Uso: load_tags <arquivo>
load_tags() {
    local name desc aliases
    TAG_NAMES=() TAG_DESCS=() TAG_ALIASES=()
    while IFS='|' read -r name desc aliases || [ -n "$name" ]; do
        # Linhas vazias (inclusive só com espaços) e comentários ficam de fora, como no tests/check_tags.py.
        [ -n "${name//[[:space:]]/}" ] || continue
        case "$name" in "#"*) continue ;; esac
        TAG_NAMES+=("$name")
        TAG_DESCS+=("$desc")
        TAG_ALIASES+=("$aliases")
    done < "$1"
}

# Retorna 0 se o argumento é uma tag da lista, um apelido dela ou "all" (a tag padrão do Ansible).
# Uso: tag_known <nome>
tag_known() {
    local i alias
    [ "$1" = all ] && return 0
    for i in "${!TAG_NAMES[@]}"; do
        [ "$1" = "${TAG_NAMES[i]}" ] && return 0
        for alias in ${TAG_ALIASES[i]}; do
            [ "$1" = "$alias" ] && return 0
        done
    done
    return 1
}

#!/usr/bin/env bash
# Funções compartilhadas por scripts/workstation.sh e scripts/interactive.sh (carregadas com "source").

# Mostra um argumento como ele precisa ser digitado no shell: entre aspas simples quando tem caracteres especiais.
# O printf %q escaparia até as vírgulas das tags; aqui só vai entre aspas o que precisa.
shell_quote() {
    local q="'\\''"
    case "$1" in
        "") printf "''" ;;
        *[!A-Za-z0-9_./:=,@%+-]*) printf "'%s'" "${1//\'/$q}" ;;
        *) printf '%s' "$1" ;;
    esac
}

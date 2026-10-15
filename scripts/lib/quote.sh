#!/usr/bin/env bash
# Funções compartilhadas por scripts/workstation.sh e scripts/interactive.sh (carregadas com "source").

# Monta uma linha de comando como ela precisa ser digitada no shell e a grava na variável indicada: cada argumento vai
# entre aspas simples só quando tem caracteres especiais (o printf %q escaparia até as vírgulas das tags). Grava com
# printf -v, sem um subshell por argumento.
# Uso: shell_join <variável> <argumentos…>
shell_join() {
    local _sj_var="$1" _sj_line="" _sj_arg _sj_q="'\\''"
    shift
    for _sj_arg in "$@"; do
        case "$_sj_arg" in
            "") _sj_arg="''" ;;
            *[!A-Za-z0-9_./:=,@%+-]*) _sj_arg="'${_sj_arg//\'/$_sj_q}'" ;;
        esac
        _sj_line+="${_sj_line:+ }$_sj_arg"
    done
    printf -v "$_sj_var" '%s' "$_sj_line"
}

#!/usr/bin/env bash
# ==============================================================================
# Workstation Ansible - ponto de entrada do provisionamento
# Uso: scripts/workstation.sh [comando] [opções] [-- argumentos do ansible-playbook]
# Sem comando, abre o wizard (scripts/interactive.sh). Veja "help".
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# Os caminhos abaixo são relativos à raiz do repositório, então o script funciona chamado de qualquer pasta.
cd "$REPO_DIR"

# Cores e saída do Ansible em tempo real, inclusive quando a saída não é um terminal.
export ANSIBLE_FORCE_COLOR=1
export PYTHONUNBUFFERED=1

PROG="./scripts/workstation.sh"
PLAYBOOK="playbooks/site.yml"
SANDBOX_DIR="tests/sandbox"

if command -v tput >/dev/null 2>&1; then
    GREEN="$(tput -Txterm setaf 2 2>/dev/null || true)"
    YELLOW="$(tput -Txterm setaf 3 2>/dev/null || true)"
    RESET="$(tput -Txterm sgr0 2>/dev/null || true)"
else
    GREEN="" YELLOW="" RESET=""
fi

# --- Opções (defaults) ---
command=""
profile="default"
tags="all"
dry_run=0
print_only=0
distro="void"
ip=""
user=""
jump_ip=""
jump_user=""
extra_args=()
has_extra=0
# Nomes das opções passadas, para recusar as que não se aplicam ao comando.
used_opts=" "

usage_error() {
    echo "Erro: $1" >&2
    echo "Veja: $PROG help" >&2
    exit 2
}

show_help() {
    cat <<EOF

${YELLOW}Workstation Ansible${RESET}

Uso: $PROG [comando] [opções] [-- argumentos do ansible-playbook]

  ${GREEN}(sem comando)${RESET}    Inicia o assistente interativo de provisionamento.
  ${GREEN}local${RESET}            Provisiona esta máquina (localhost).
  ${GREEN}remote${RESET}           Provisiona servidor remoto via SSH (exige --ip).
  ${GREEN}tunnel${RESET}           Provisiona via Bastion Host (exige --ip, --jump-ip e --jump-user).
  ${GREEN}sandbox${RESET}          Provisiona em container Docker isolado (void, ubuntu, fedora, arch).
  ${GREEN}sandbox-shell${RESET}    Acessa o terminal interativo do container sandbox.
  ${GREEN}sandbox-clean${RESET}    Para e remove o container sandbox.
  ${GREEN}help${RESET}             Mostra esta ajuda.
  ${GREEN}help-docs${RESET}        Exibe a documentação detalhada e exemplos (docs/USAGE.md).

  ${YELLOW}Opções:${RESET}
    --profile NOME       local, remote, tunnel, sandbox: perfil em profiles/ (default: default)
    --tags LISTA         local, remote, tunnel, sandbox: tags separadas por vírgula (default: all)
                         devtools, languages, python, node, rust, go, docker, zsh, editors, ui, dotfiles
    --dry-run            local, remote, tunnel: modo simulação (--check --diff); o sandbox ainda o ignora (#12)
    --distro NOME        sandbox, sandbox-shell, sandbox-clean: void, ubuntu, fedora, arch (default: void)
    --ip HOST            remote, tunnel: um único host de destino (obrigatório)
    --user USUARIO       remote, tunnel: usuário SSH no destino (default: o usuário atual, whoami)
    --jump-ip HOST       tunnel: host do Bastion (obrigatório)
    --jump-user USUARIO  tunnel: usuário do Bastion (obrigatório)
    --print              Mostra os comandos sem executá-los.
    -- ARGS              local, remote, tunnel, sandbox: argumentos extras para o ansible-playbook (ex.: -- -vvv)

  As opções aceitam "--opção valor" e "--opção=valor".

EOF
}

# --- Leitura dos argumentos ---

set_option() {
    local name="$1" value="$2"
    case "$name" in
        profile)   profile="$value" ;;
        tags)      tags="$value" ;;
        distro)    distro="$value" ;;
        ip)        ip="$value" ;;
        user)      user="$value" ;;
        jump-ip)   jump_ip="$value" ;;
        jump-user) jump_user="$value" ;;
        *)         usage_error "opção desconhecida: --$name" ;;
    esac
    used_opts+="$name "
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --)
                shift
                extra_args=("$@")
                has_extra=1
                break
                ;;
            -h|--help)
                command="help"
                ;;
            --dry-run)
                dry_run=1
                used_opts+="dry-run "
                ;;
            --print)
                print_only=1
                used_opts+="print "
                ;;
            --dry-run=*|--print=*)
                usage_error "a opção ${1%%=*} não aceita valor"
                ;;
            --*=*)
                local name="${1%%=*}"
                set_option "${name#--}" "${1#*=}"
                ;;
            --profile|--tags|--distro|--ip|--user|--jump-ip|--jump-user)
                # "--tags --print" usaria a opção seguinte como valor; um valor que começa com "-" vai em --opção=valor.
                [ $# -ge 2 ] && [[ "$2" != -* ]] || usage_error "a opção $1 exige um valor"
                set_option "${1#--}" "$2"
                shift
                ;;
            -*)
                usage_error "opção desconhecida: $1"
                ;;
            *)
                [ -z "$command" ] || usage_error "argumento inesperado: $1 (um comando por vez)"
                command="$1"
                ;;
        esac
        shift
    done
}

# Recusa as opções que não se aplicam ao comando: "local --ip x" não deve provisionar o localhost em silêncio.
check_options() {
    local allowed="$1" extra_ok="$2" opt
    for opt in $used_opts; do
        case " $allowed " in
            *" $opt "*) ;;
            *) usage_error "a opção --$opt não se aplica ao comando '${command:-wizard}'" ;;
        esac
    done
    if [ "$has_extra" -eq 1 ] && [ "$extra_ok" -eq 0 ]; then
        usage_error "argumentos depois de -- não se aplicam ao comando '${command:-wizard}'"
    fi
}

# Valida um valor que vira um único host ou usuário na linha de comando. Os espaços nas pontas são descartados (um
# espaço digitado no wizard continua valendo); vazio, espaço no meio ou vírgula viram vários hosts no inventário
# "<ip>," ou quebram o ProxyCommand. Devolve o valor limpo em REPLY.
single_value() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    [ -n "$value" ] || return 1
    case "$value" in
        *[[:space:],]*) return 1 ;;
    esac
    REPLY="$value"
}

require_single() {
    local value="$1" message="$2" usage="$3"
    single_value "$value" || usage_error "$message: $usage"
}

# --- Execução ---

# Mostra um argumento como ele precisa ser digitado no shell: entre aspas simples quando tem caracteres especiais.
quote_arg() {
    local q="'\\''"
    case "$1" in
        "") printf "''" ;;
        *[!A-Za-z0-9_./:=,@%+-]*) printf "'%s'" "${1//\'/$q}" ;;
        *) printf '%s' "$1" ;;
    esac
}

# Mostra o comando (como o make fazia) e o executa; com --print, só mostra.
run_cmd() {
    local arg line=""
    for arg in "$@"; do
        line+="${line:+ }$(quote_arg "$arg")"
    done
    printf '%s\n' "$line"
    [ "$print_only" -eq 1 ] || "$@"
}

# Mensagens de progresso; com --print, a saída fica só com os comandos.
msg() {
    [ "$print_only" -eq 1 ] || echo -e "$1"
}

mode_label() {
    if [ "$dry_run" -eq 1 ]; then echo "[DRY RUN]"; else echo "[EXECUÇÃO]"; fi
}

# ansible-playbook com -K, tags, perfil, simulação e argumentos extras, sem o inventário. Resultado em ANSIBLE_CMD.
ansible_cmd() {
    ANSIBLE_CMD=(ansible-playbook "$PLAYBOOK" -K --tags "$tags" -e "profile=$profile")
    [ "$dry_run" -eq 0 ] || ANSIBLE_CMD+=(--check --diff)
    ANSIBLE_CMD+=(${extra_args[@]+"${extra_args[@]}"})
}

run_local() {
    ansible_cmd
    msg "${GREEN}>> Iniciando $(mode_label) LOCAL [Tags: ${tags}]...${RESET}"
    run_cmd "${ANSIBLE_CMD[@]}" -i "localhost," -c local
}

run_remote() {
    ansible_cmd
    msg "${GREEN}>> Iniciando $(mode_label) REMOTE em ${ip} [Tags: ${tags}]...${RESET}"
    run_cmd "${ANSIBLE_CMD[@]}" -i "${ip}," -u "$user"
}

run_tunnel() {
    ansible_cmd
    msg "${GREEN}>> Iniciando $(mode_label) TUNNEL via ${jump_ip} para ${ip}...${RESET}"
    run_cmd "${ANSIBLE_CMD[@]}" -i "${ip}," -u "$user" \
        "--ssh-common-args=-o ProxyCommand=\"ssh -W %h:%p -q ${jump_user}@${jump_ip}\""
}

sandbox_image() { echo "workstation-sandbox-image-${distro}"; }
sandbox_container() { echo "workstation-sandbox-${distro}"; }

run_sandbox() {
    local image container
    image="$(sandbox_image)"
    container="$(sandbox_container)"

    msg "${GREEN}>> Preparando ambiente Sandbox Docker (Distro: ${distro})...${RESET}"
    # O sandbox monta o próprio ansible-playbook: sem -K (o sudo do usuário dev é NOPASSWD) e, por enquanto, sem
    # --check --diff (#12).
    [ "$dry_run" -eq 0 ] || msg "${YELLOW}Aviso: o sandbox ainda ignora --dry-run (#12); a execução é real.${RESET}"
    msg "${GREEN}>> Construindo imagem ${image}...${RESET}"
    run_cmd docker build -t "$image" -f "${SANDBOX_DIR}/Dockerfile.${distro}" "${SANDBOX_DIR}/"
    # Recria o container a cada execução (#51).
    msg "${GREEN}>> Garantindo que o container ${container} esteja rodando...${RESET}"
    run_cmd docker rm -f "$container" 2>/dev/null || true
    run_cmd docker run -d --name "$container" "$image"
    msg "${GREEN}>> Executando Ansible via Docker Connection no container ${container} [Tags: ${tags}]...${RESET}"
    run_cmd ansible-playbook "$PLAYBOOK" --tags "$tags" -e "profile=$profile" \
        ${extra_args[@]+"${extra_args[@]}"} -i "${container}," -c docker -u dev

    msg ""
    msg "${GREEN}======================================================================${RESET}"
    msg "${GREEN} SUCCESS: Provisionamento Sandbox concluído!${RESET}"
    msg "${YELLOW} Para entrar no container sandbox e testar a instalação:${RESET}"
    msg "   ${GREEN}${PROG} sandbox-shell --distro ${distro}${RESET}"
    msg "   ou: ${GREEN}docker exec -it ${container} /bin/bash${RESET}"
    msg "${YELLOW} Para remover o container sandbox:${RESET}"
    msg "   ${GREEN}${PROG} sandbox-clean --distro ${distro}${RESET}"
    msg "${GREEN}======================================================================${RESET}"
}

run_sandbox_shell() {
    local container
    container="$(sandbox_container)"
    msg "${GREEN}>> Entrando no container sandbox (${container})...${RESET}"
    run_cmd docker exec -it "$container" /bin/bash
}

run_sandbox_clean() {
    local container
    container="$(sandbox_container)"
    msg "${GREEN}>> Parando e removendo container sandbox (${container})...${RESET}"
    run_cmd docker rm -f "$container" 2>/dev/null || true
}

main() {
    parse_args "$@"

    local remote_usage="$PROG remote --ip x.x.x.x [--user usuario]"
    local tunnel_usage="$PROG tunnel --ip x.x.x.x --jump-ip y.y.y.y --jump-user usuario [--user usuario]"
    local provision_opts="profile tags dry-run print"

    case "$command" in
        "")
            check_options "" 0
            # O wizard exige bash >= 4.4 (docs/ARCHITECTURE.md#wizard-e-camada-de-interface).
            exec bash "$SCRIPT_DIR/interactive.sh"
            ;;
        help)
            show_help
            ;;
        help-docs)
            check_options "" 0
            cat docs/USAGE.md
            echo ''
            ;;
        local)
            check_options "$provision_opts" 1
            run_local
            ;;
        remote|tunnel)
            if [ "$command" = "remote" ]; then
                check_options "$provision_opts ip user" 1
                require_single "$ip" "Defina um único IP de destino" "$remote_usage"
                ip="$REPLY"
            else
                check_options "$provision_opts ip user jump-ip jump-user" 1
                require_single "$ip" "Defina um único IP de destino" "$tunnel_usage"
                ip="$REPLY"
                require_single "$jump_ip" "Defina um único IP do Bastion" "$tunnel_usage"
                jump_ip="$REPLY"
                require_single "$jump_user" "Defina um único usuário do Bastion" "$tunnel_usage"
                jump_user="$REPLY"
            fi
            # Sem --user, o usuário SSH é o usuário atual (#35: o Makefile usava o $USER do ambiente). Um --user vazio é
            # recusado abaixo, em vez de cair no default.
            case "$used_opts" in
                *" user "*) ;;
                *) user="$(whoami)" ;;
            esac
            require_single "$user" "Defina um único usuário SSH" \
                "$([ "$command" = "remote" ] && echo "$remote_usage" || echo "$tunnel_usage")"
            user="$REPLY"
            if [ "$command" = "remote" ]; then run_remote; else run_tunnel; fi
            ;;
        sandbox|sandbox-shell|sandbox-clean)
            if [ "$command" = "sandbox" ]; then
                check_options "$provision_opts distro" 1
                [ -f "${SANDBOX_DIR}/Dockerfile.${distro}" ] ||
                    usage_error "Dockerfile para a distro '${distro}' não encontrado em ${SANDBOX_DIR}/Dockerfile.${distro}"
                run_sandbox
            else
                check_options "distro print" 0
                if [ "$command" = "sandbox-shell" ]; then run_sandbox_shell; else run_sandbox_clean; fi
            fi
            ;;
        *)
            usage_error "comando desconhecido: $command"
            ;;
    esac
}

main "$@"

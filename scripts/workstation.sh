#!/usr/bin/env bash
# ==============================================================================
# Workstation Ansible - ponto de entrada do provisionamento
# Uso: scripts/workstation.sh [comando] [opções] [-- argumentos do ansible-playbook]
# Sem comando, abre o wizard (scripts/interactive.sh). Veja "help".
# ==============================================================================

set -euo pipefail

# Com CDPATH exportado, o "cd" abaixo imprimiria a pasta, e o caminho calculado ficaria com duas linhas.
unset CDPATH

# readlink -f: chamado por um symlink (ex.: ~/bin/ws), o script ainda acha o repositório e a lib. Onde o readlink não
# tem -f (macOS antes do 12.3), vale o caminho da chamada, que funciona sem symlink.
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=scripts/lib/quote.sh
source "$SCRIPT_DIR/lib/quote.sh"

# Cores e saída do Ansible em tempo real, inclusive quando a saída não é um terminal.
export ANSIBLE_FORCE_COLOR=1
export PYTHONUNBUFFERED=1
# O script não muda de pasta, para que caminhos relativos depois de "--" (-e @vars.yml, --vault-password-file)
# continuem relativos à pasta de quem chama. Por isso os caminhos do repositório são absolutos, e o ansible.cfg do
# projeto vai no próprio comando, como "env ANSIBLE_CONFIG=… ansible-playbook" (um ANSIBLE_CONFIG já definido continua
# valendo, como antes): o comando mostrado pelo --print funciona colado em qualquer pasta.
ANSIBLE_CONFIG_FILE="${ANSIBLE_CONFIG:-$REPO_DIR/ansible.cfg}"

# Nomes simples (perfil, host, usuário do Bastion) e logins SSH, que também aceitam "@" (jdoe@corp.example, do SSSD).
NAME_RE='^[A-Za-z0-9_][A-Za-z0-9._-]*$'
LOGIN_RE='^[A-Za-z0-9_][A-Za-z0-9._@-]*$'

# Comando mostrado nas mensagens e nas sugestões: o caminho pelo qual o script foi chamado, que funciona na pasta atual.
# O atalho da raiz (./workstation.sh) e este script, ao abrir o wizard, informam esse caminho em WORKSTATION_PROG, que só
# muda o texto exibido, nunca o que é executado. "bash workstation.sh", chamado na pasta do arquivo, vira
# "./workstation.sh"; um nome achado no PATH fica como está.
PROG_PATH="${WORKSTATION_PROG:-$0}"
# Lida, a variável sai do ambiente: não passa ao ansible-playbook e ao docker, e o wizard a recebe explicitamente.
unset WORKSTATION_PROG
case "$PROG_PATH" in
    */*) ;;
    *) [ ! -e "$PROG_PATH" ] || PROG_PATH="./$PROG_PATH" ;;
esac
shell_join PROG "$PROG_PATH"
PLAYBOOK="$REPO_DIR/playbooks/site.yml"
SANDBOX_DIR="$REPO_DIR/tests/sandbox"

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
want_help=0
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
    --profile NOME       local, remote, tunnel, sandbox: perfil profiles/NOME.yml (default: default)
    --tags LISTA         local, remote, tunnel, sandbox: tags separadas por vírgula (default: all)
                         devtools, languages, python, node, rust, go, docker, zsh, editors, ui, dotfiles
    --dry-run            local, remote, tunnel, sandbox: modo simulação (--check --diff)
    --distro NOME        sandbox, sandbox-shell, sandbox-clean: void, ubuntu, fedora, arch (default: void)
    --ip HOST            remote, tunnel: um único host de destino, hostname ou IPv4 (obrigatório)
    --user USUARIO       remote, tunnel: usuário SSH no destino (default: o usuário atual, whoami; aceita @)
    --jump-ip HOST       tunnel: host do Bastion (obrigatório)
    --jump-user USUARIO  tunnel: usuário do Bastion (obrigatório)
    --print              Mostra os comandos sem executá-los.
    -- ARGS              local, remote, tunnel, sandbox: argumentos extras para o ansible-playbook (ex.: -- -vvv)

  As opções aceitam "--opção valor" e "--opção=valor" (um valor que começa com "-" só na segunda forma).
  Hosts e usuários aceitam letras, números e . _ - (o --user também @); para IPv6 ou outra porta, use um alias
  do ~/.ssh/config.

EOF
}

# --- Leitura dos argumentos ---

set_option() {
    local name="$1" value="$2"
    # Um valor vazio nunca é o que se quer: "--tags=" rodaria só as tarefas "always" e terminaria com sucesso.
    [ -n "$value" ] || usage_error "a opção --$name exige um valor"
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
                # Em qualquer posição: "--help local" e "local --help" mostram a ajuda.
                want_help=1
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

# Valida um host ou usuário e o atribui à variável indicada. Os espaços nas pontas são descartados (um espaço digitado
# no wizard continua valendo). Só passam letras, números e . _ -, sem "-" no início: uma vírgula ou um espaço viraria
# outro host no inventário "<ip>,"; aspas, $, ; ou % quebrariam o ProxyCommand, que o ssh executa num shell local, ou
# virariam tokens do ssh; um "-" no início viraria opção do ssh. IPv6 e host:porta também ficam de fora, porque o
# "ssh -W %h:%p" e o "usuario@host" do ProxyCommand não os entendem: para eles, use um alias do ~/.ssh/config.
# O tipo "login" (--user) aceita também "@": ele só vira o -u do ansible-playbook e nunca entra no ProxyCommand.
# Uso: require_value <variável> <valor> <name|login> <mensagem> <uso>
require_value() {
    local var="$1" value="$2" kind="$3" message="$4" usage="$5" pattern="$NAME_RE" chars=". _ -"
    if [ "$kind" = login ]; then
        pattern="$LOGIN_RE" chars=". _ - @"
    fi
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    [[ "$value" =~ $pattern ]] || usage_error "$message (letras, números e $chars): $usage"
    printf -v "$var" '%s' "$value"
}

# Sem --user, o usuário SSH é o usuário atual (#35: antes, ele vinha do $USER do ambiente). Um --user vazio é recusado,
# em vez de cair no default.
require_ssh_user() {
    case "$used_opts" in
        *" user "*) ;;
        *) user="$(whoami)" ;;
    esac
    require_value user "$user" login "Defina um único usuário SSH" "$1"
}

# O perfil vira "-e profile=<nome>", que o Ansible lê como uma lista key=value separada por espaços: "default x=y"
# definiria outra variável. Só passam nomes simples com um arquivo profiles/<nome>.yml.
require_profile() {
    local available
    if [[ ! "$profile" =~ $NAME_RE ]] || [ ! -f "$REPO_DIR/profiles/${profile}.yml" ]; then
        available="$(cd "$REPO_DIR/profiles" && for f in *.yml; do printf '%s ' "${f%.yml}"; done)"
        usage_error "perfil '${profile}' não encontrado em profiles/ (disponíveis: ${available% })"
    fi
}

# Os três comandos de sandbox só aceitam uma distro com Dockerfile: um --distro errado no sandbox-clean removeria um
# container que não existe e sairia com sucesso.
require_distro() {
    [ -f "${SANDBOX_DIR}/Dockerfile.${distro}" ] ||
        usage_error "Dockerfile para a distro '${distro}' não encontrado em ${SANDBOX_DIR}/Dockerfile.${distro}"
}

# --- Execução ---

# Mostra o comando e o executa; com --print, só mostra.
run_cmd() {
    local line
    shell_join line "$@"
    printf '%s\n' "$line"
    [ "$print_only" -eq 1 ] || "$@"
}

# Mensagens de progresso; com --print, a saída fica só com os comandos.
msg() {
    [ "$print_only" -eq 1 ] || echo -e "$1"
}

# ansible-playbook com o ansible.cfg, tags, perfil e argumentos extras, sem o inventário. Resultado em ANSIBLE_CMD.
# Uso: ansible_cmd <pedir a senha do sudo (-K): 0|1> <simulação (--check --diff): 0|1>
ansible_cmd() {
    local ask_become_pass="$1" check="$2"
    ANSIBLE_CMD=(env "ANSIBLE_CONFIG=$ANSIBLE_CONFIG_FILE" ansible-playbook "$PLAYBOOK")
    [ "$ask_become_pass" -eq 0 ] || ANSIBLE_CMD+=(-K)
    ANSIBLE_CMD+=(--tags "$tags" -e "profile=$profile")
    [ "$check" -eq 0 ] || ANSIBLE_CMD+=(--check --diff)
    ANSIBLE_CMD+=(${extra_args[@]+"${extra_args[@]}"})
}

run_local() {
    ansible_cmd 1 "$dry_run"
    msg "${GREEN}>> Iniciando ${MODE_LABEL} LOCAL [Tags: ${tags}]...${RESET}"
    run_cmd "${ANSIBLE_CMD[@]}" -i "localhost," -c local
}

run_remote() {
    ansible_cmd 1 "$dry_run"
    msg "${GREEN}>> Iniciando ${MODE_LABEL} REMOTE em ${ip} [Tags: ${tags}]...${RESET}"
    run_cmd "${ANSIBLE_CMD[@]}" -i "${ip}," -u "$user"
}

run_tunnel() {
    ansible_cmd 1 "$dry_run"
    msg "${GREEN}>> Iniciando ${MODE_LABEL} TUNNEL via ${jump_ip} para ${ip}...${RESET}"
    run_cmd "${ANSIBLE_CMD[@]}" -i "${ip}," -u "$user" \
        "--ssh-common-args=-o ProxyCommand=\"ssh -W %h:%p -q ${jump_user}@${jump_ip}\""
}

run_sandbox() {
    local image="$SANDBOX_IMAGE" container="$SANDBOX_CONTAINER"

    # Sem -K: o sudo do usuário dev é NOPASSWD. Com --dry-run, o playbook roda em --check --diff sobre o container
    # recém-criado.
    ansible_cmd 0 "$dry_run"
    msg "${GREEN}>> Preparando ambiente Sandbox Docker (Distro: ${distro})...${RESET}"
    msg "${GREEN}>> Construindo imagem ${image}...${RESET}"
    run_cmd docker build -t "$image" -f "${SANDBOX_DIR}/Dockerfile.${distro}" "${SANDBOX_DIR}/"
    # Recria o container a cada execução (#51).
    msg "${GREEN}>> Garantindo que o container ${container} esteja rodando...${RESET}"
    run_cmd docker rm -f "$container" 2>/dev/null || true
    run_cmd docker run -d --name "$container" "$image"
    msg "${GREEN}>> Executando ${MODE_LABEL} via Docker Connection no container ${container} [Tags: ${tags}]...${RESET}"
    run_cmd "${ANSIBLE_CMD[@]}" -i "${container}," -c docker -u dev

    msg ""
    msg "${GREEN}======================================================================${RESET}"
    if [ "$dry_run" -eq 1 ]; then
        msg "${GREEN} SUCCESS: Simulação no Sandbox concluída (--dry-run): nada foi aplicado no container.${RESET}"
        msg "${YELLOW} Para entrar no container sandbox (sem o provisionamento):${RESET}"
    else
        msg "${GREEN} SUCCESS: Provisionamento Sandbox concluído!${RESET}"
        msg "${YELLOW} Para entrar no container sandbox e testar a instalação:${RESET}"
    fi
    msg "   ${GREEN}${PROG} sandbox-shell --distro ${distro}${RESET}"
    msg "   ou: ${GREEN}docker exec -it ${container} /bin/bash${RESET}"
    msg "${YELLOW} Para remover o container sandbox:${RESET}"
    msg "   ${GREEN}${PROG} sandbox-clean --distro ${distro}${RESET}"
    msg "${GREEN}======================================================================${RESET}"
}

run_sandbox_shell() {
    local container="$SANDBOX_CONTAINER"
    msg "${GREEN}>> Entrando no container sandbox (${container})...${RESET}"
    run_cmd docker exec -it "$container" /bin/bash
}

run_sandbox_clean() {
    local container="$SANDBOX_CONTAINER"
    msg "${GREEN}>> Parando e removendo container sandbox (${container})...${RESET}"
    run_cmd docker rm -f "$container" 2>/dev/null || true
}

main() {
    parse_args "$@"

    # Comando e opções são conferidos antes da ajuda: "bogus --help" e "local --ip x --help" saem com erro.
    local provision_opts="profile tags dry-run print"
    case "$command" in
        ""|help|help-docs) check_options "" 0 ;;
        local)             check_options "$provision_opts" 1 ;;
        remote)            check_options "$provision_opts ip user" 1 ;;
        tunnel)            check_options "$provision_opts ip user jump-ip jump-user" 1 ;;
        sandbox)           check_options "$provision_opts distro" 1 ;;
        sandbox-shell|sandbox-clean) check_options "distro print" 0 ;;
        *)                 usage_error "comando desconhecido: $command" ;;
    esac

    if [ "$want_help" -eq 1 ]; then
        show_help
        return
    fi

    # Valores fixos depois da leitura dos argumentos.
    if [ "$dry_run" -eq 1 ]; then MODE_LABEL="[DRY RUN]"; else MODE_LABEL="[EXECUÇÃO]"; fi
    SANDBOX_IMAGE="workstation-sandbox-image-${distro}"
    SANDBOX_CONTAINER="workstation-sandbox-${distro}"

    local remote_usage="$PROG remote --ip x.x.x.x [--user usuario]"
    local tunnel_usage="$PROG tunnel --ip x.x.x.x --jump-ip y.y.y.y --jump-user usuario [--user usuario]"

    case "$command" in
        "")
            # O wizard exige bash >= 4.4 (docs/ARCHITECTURE.md#wizard-e-camada-de-interface). Ele mostra o comando
            # com o mesmo caminho pelo qual este script foi chamado.
            WORKSTATION_PROG="$PROG_PATH" exec bash "$SCRIPT_DIR/interactive.sh"
            ;;
        help)
            show_help
            ;;
        help-docs)
            cat "$REPO_DIR/docs/USAGE.md"
            echo ''
            ;;
        local)
            require_profile
            run_local
            ;;
        remote)
            require_profile
            require_value ip "$ip" name "Defina um único IP de destino" "$remote_usage"
            require_ssh_user "$remote_usage"
            run_remote
            ;;
        tunnel)
            require_profile
            require_value ip "$ip" name "Defina um único IP de destino" "$tunnel_usage"
            require_value jump_ip "$jump_ip" name "Defina um único IP do Bastion" "$tunnel_usage"
            require_value jump_user "$jump_user" name "Defina um único usuário do Bastion" "$tunnel_usage"
            require_ssh_user "$tunnel_usage"
            run_tunnel
            ;;
        sandbox)
            require_profile
            require_distro
            run_sandbox
            ;;
        sandbox-shell)
            require_distro
            run_sandbox_shell
            ;;
        sandbox-clean)
            require_distro
            run_sandbox_clean
            ;;
    esac
}

main "$@"

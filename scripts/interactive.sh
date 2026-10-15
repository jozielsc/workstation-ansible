#!/usr/bin/env bash
# ==============================================================================
# Workstation Ansible - Interactive Provisioning Wizard
# Inspired by Proxmox VE Community Scripts
# ==============================================================================

set -euo pipefail

# --- ANSI Colors ---
BOLD='\033[1m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- Root Dir Resolution ---
# Com CDPATH exportado, o "cd" abaixo imprimiria a pasta, e o caminho calculado ficaria com duas linhas.
unset CDPATH
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=scripts/lib/quote.sh
source "$SCRIPT_DIR/lib/quote.sh"

show_banner() {
    # Sem TERM, o clear falha; com set -e, isso derrubaria o wizard no modo cli.
    clear 2>/dev/null || true
    echo -e "${CYAN}${BOLD}"
    cat << "EOF"
  _  _  _             _         _   _                  _           _     _ 
 | || || | ___  _ __ | | __ ___| |_| |_  __ _  ___  __| | ___ _ __ | |   | |
 | || || |/ _ \| '__|| |/ /___/ __| __|/ _` |/ _ \/ _` |/ _ \ '_ \| |   |_|
 | || || | (_) | |   |   <   | |_| |_| (_| |  __/ (_| |  __/ | | |_|    _ 
 |_||_||_|\___/|_|   |_|\_\   \__|\__|\__,_|\___|\__,_|\___|_| |_(_)   (_)
EOF
    echo -e "${YELLOW}           Workstation Ansible - Provisioning Wizard${NC}\n"
}

# Converte uma seleção numérica (1..max) no índice base 0 e o imprime; falha se for inválida.
# Zeros à esquerda são ignorados (08 = 8) e mais de 9 dígitos significativos é recusado, para não estourar a aritmética do bash.
parse_index() {
    local value="$1"
    local max="$2"
    [[ "$value" =~ ^[0-9]+$ ]] || return 1
    value="${value#"${value%%[!0]*}"}"
    [[ "$value" =~ ^[1-9][0-9]{0,8}$ ]] || return 1
    [ "$value" -le "$max" ] || return 1
    echo $((value - 1))
}

# --- Camada de interface ---
# Os passos do wizard só conversam com ui_menu, ui_checklist, ui_input, ui_yesno e ui_text, e leem o resultado em:
#   UI_ACTION  ok | no (só em ui_yesno) | back | cancel
#   UI_VALUE   item escolhido (ui_menu) ou texto digitado (ui_input)
#   UI_LIST    itens marcados (ui_checklist)
# O motor fica escondido aqui, na ordem dialog > whiptail > cli (TUI_ENGINE força um, sem fallback). Cada motor tem um
# adaptador que traduz Back e Cancel para o que ele oferece. Se um motor falha, ele sai de UI_ENGINES e o mesmo diálogo
# é repetido no próximo. Por isso as funções não são chamadas com $(...): a troca de motor precisa valer para o resto do wizard.

UI_ENGINES=()
UI_ACTION=""
UI_VALUE=""
UI_LIST=()
UI_RC=0
UI_OUT=""
UI_ERROR=""
UI_TMP_DIR=""

ui_warn() {
    printf '%b%s%b\n' "$YELLOW" "$*" "$NC" >&2
}

# Pausa para o aviso não sumir sob a próxima tela. Sem terminal, segue direto.
ui_pause() {
    if [ -t 0 ] && [ -t 2 ]; then
        read -rp "Pressione Enter para continuar..." _ || true
    fi
}

ui_fatal() {
    ui_warn "$*"
    exit 1
}

# Sem TUI_ENGINE, detecta os motores na ordem dialog > whiptail > cli, com fallback. Com TUI_ENGINE, usa só o motor
# pedido, sem fallback: quem força um motor (por exemplo, para testá-lo) não pode acabar usando outro sem perceber.
ui_init() {
    local engine
    # Um diretório só para os temporários (stderr do motor, texto do help), removido na saída, inclusive no Ctrl-C.
    UI_TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$UI_TMP_DIR"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    # dialog e whiptail desenham no terminal e leem dele: sem tty em stdin ou stdout, os dois falham. Checar uma vez
    # aqui evita um aviso e uma pausa por motor a cada diálogo.
    local has_tty=1
    { [ -t 0 ] && [ -t 1 ]; } || has_tty=0

    if [ -n "${TUI_ENGINE:-}" ]; then
        case "$TUI_ENGINE" in
            dialog|whiptail)
                command -v "$TUI_ENGINE" >/dev/null 2>&1 || ui_fatal "TUI_ENGINE=$TUI_ENGINE, mas o $TUI_ENGINE não está instalado."
                [ "$has_tty" -eq 1 ] || ui_fatal "TUI_ENGINE=$TUI_ENGINE precisa de um terminal em stdin e stdout."
                ;;
            cli) ;;
            *) ui_fatal "TUI_ENGINE=$TUI_ENGINE não é suportado (use dialog, whiptail ou cli)." ;;
        esac
        UI_ENGINES=("$TUI_ENGINE")
        return 0
    fi

    for engine in dialog whiptail; do
        if command -v "$engine" >/dev/null 2>&1; then
            UI_ENGINES+=("$engine")
        fi
    done
    if [ "${#UI_ENGINES[@]}" -gt 0 ] && [ "$has_tty" -eq 0 ]; then
        ui_warn "stdin ou stdout não é um terminal: dialog e whiptail não funcionam; usando o modo cli."
        UI_ENGINES=()
        ui_pause
    fi
    UI_ENGINES+=(cli)
}

ui_engine_failed() {
    local failed="${UI_ENGINES[0]}"
    if [ -n "${TUI_ENGINE:-}" ]; then
        ui_fatal "O $failed falhou: ${UI_ERROR} (TUI_ENGINE=$TUI_ENGINE força o motor, sem fallback)."
    fi
    UI_ENGINES=("${UI_ENGINES[@]:1}")
    ui_warn "O $failed falhou: ${UI_ERROR}"
    ui_warn "Continuando com o ${UI_ENGINES[0]}."
    ui_pause
}

# Roda o dialog ou o whiptail e guarda o código de saída em UI_RC e o valor em UI_OUT. O valor sai pelo fd 3, a tela
# vai para o terminal (fd 4, o stdout do wizard) e o stderr para um arquivo: assim uma mensagem de erro do motor não se
# mistura ao valor. Devolve 1 quando o motor falhou (mensagem em UI_ERROR): um código fora de 0/1/2/3/255, ou stderr não
# vazio com código diferente de 0 (o whiptail sai com 1 numa opção inválida, igual ao Cancel). O terminal é checado
# uma vez, em ui_init.
ui_tui_exec() {
    local engine="$1"
    shift
    local err_file="$UI_TMP_DIR/stderr"
    UI_RC=0
    UI_OUT=""
    UI_ERROR=""
    { UI_OUT=$("$engine" --output-fd 3 --backtitle "Workstation Ansible" "$@" 3>&1 1>&4 2>"$err_file"); } 4>&1 || UI_RC=$?
    UI_ERROR=$(<"$err_file")
    case "$UI_RC" in
        0) return 0 ;;
        1|2|3|255) [ -z "$UI_ERROR" ] && return 0 ;;
        *) [ -n "$UI_ERROR" ] || UI_ERROR="saiu com o código $UI_RC" ;;
    esac
    return 1
}

# No whiptail, o botão "Voltar/Cancelar" abre este menu, porque ele não tem um terceiro botão para o Back.
# "Continuar nesta tela" reabre o diálogo com os valores de quando ela foi aberta: com o segundo botão, o whiptail não
# devolve o que foi editado.
ui_tui_back_or_cancel() {
    local engine="$1"
    local title="$2"
    # Itens sem acento: o newt mede a largura da lista em bytes e cortaria o texto ("à" ocupa dois).
    ui_tui_exec "$engine" --title "$title" --notags --nocancel --menu "O que deseja fazer?" 12 50 3 \
        back "Voltar para a tela anterior" \
        cancel "Cancelar o wizard" \
        stay "Continuar nesta tela" || return 1
    UI_ACTION="stay"
    # Esc fecha só este menu e volta à tela.
    if [ "$UI_RC" -eq 0 ]; then
        case "$UI_OUT" in
            back|cancel) UI_ACTION="$UI_OUT" ;;
        esac
    fi
    return 0
}

# Adaptador do dialog e do whiptail. Códigos: 0 = OK/Yes, 1 = Cancel/No, 2 = botão help (Cancel no sim/não do dialog),
# 3 = botão extra (Back, só no dialog), 255 = Esc. O sim/não do dialog com Back ganha um quarto botão, Cancel, porque o
# No já é uma resposta. O whiptail só tem dois botões e o newt do Fedora ignora o Esc: com Back, o segundo botão vira
# "Voltar/Cancelar" e abre ui_tui_back_or_cancel, e o sim/não vira um menu, para caber sim, não e esse botão.
ui_tui() {
    local engine="$1"
    local kind="$2"
    local back="$3"
    local title="$4"
    local prompt="$5"
    shift 5

    local opts=(--title "$title")
    local box=()
    local back_menu=0
    if [ "$back" = "1" ]; then
        if [ "$engine" = "dialog" ]; then
            opts+=(--extra-button --extra-label "Back")
        else
            back_menu=1
            opts+=(--cancel-button "Voltar/Cancelar")
        fi
    fi

    case "$kind" in
        menu)
            box=(--radiolist "$prompt" 18 70 8 "$@")
            ;;
        checklist)
            # Um item por linha e sem aspas, nos dois motores.
            opts+=(--separate-output)
            box=(--checklist "$prompt" 22 75 12 "$@")
            ;;
        input)
            box=(--inputbox "$prompt" 12 65 "$1")
            ;;
        yesno)
            # O resumo da confirmação pode ter mais linhas do que cabem na altura padrão: a caixa cresce com o texto (linhas
            # quebradas na largura da caixa) até a altura do terminal; acima disso, o texto rola.
            local text_lines term_lines height
            text_lines=$(printf '%s\n' "${prompt//\\n/$'\n'}" | fold -s -w 71 | wc -l)
            term_lines=$(tput lines 2>/dev/null || echo 24)
            if [ "$back_menu" -eq 1 ]; then
                # Bordas, lista Yes/No, espaços e botões ocupam 9 linhas além do texto.
                height=$(( text_lines + 9 ))
                [ "$height" -lt 22 ] && height=22
                opts+=(--notags)
                if [ "$height" -gt "$term_lines" ]; then
                    height="$term_lines"
                    opts+=(--scrolltext)
                fi
                box=(--menu "$prompt" "$height" 75 2 yes "Yes" no "No")
            else
                # Bordas, espaços e botões ocupam 6 linhas além do texto.
                height=$(( text_lines + 6 ))
                [ "$height" -lt 20 ] && height=20
                [ "$height" -gt "$term_lines" ] && height="$term_lines"
                [ "$back" = "1" ] && opts+=(--help-button --help-label "Cancel")
                box=(--yesno "$prompt" "$height" 75)
            fi
            ;;
        text)
            [ "$engine" = "whiptail" ] && opts+=(--scrolltext)
            box=(--textbox "$1" "$2" "$3")
            ;;
    esac

    while true; do
        ui_tui_exec "$engine" "${opts[@]}" "${box[@]}" || return 1
        # Fechar o texto, com qualquer botão ou Esc, só volta à tela.
        if [ "$kind" = "text" ]; then
            UI_ACTION="ok"
            return 0
        fi
        case "$UI_RC" in
            0)
                UI_ACTION="ok"
                if [ "$kind" = "yesno" ] && [ "$back_menu" -eq 1 ] && [ "$UI_OUT" != "yes" ]; then
                    UI_ACTION="no"
                fi
                ;;
            1)
                if [ "$back_menu" -eq 1 ]; then
                    ui_tui_back_or_cancel "$engine" "$title" || return 1
                    [ "$UI_ACTION" = "stay" ] && continue
                elif [ "$kind" = "yesno" ]; then
                    UI_ACTION="no"
                else
                    UI_ACTION="cancel"
                fi
                ;;
            3)
                UI_ACTION="back"
                ;;
            2|255)
                UI_ACTION="cancel"
                ;;
        esac
        break
    done

    # Valor só com ok: depois do menu Voltar/Cancelar, UI_OUT é "back" ou "cancel", não algo que o usuário escolheu.
    [ "$UI_ACTION" = "ok" ] || return 0
    case "$kind" in
        menu)
            UI_VALUE="$UI_OUT"
            ;;
        input)
            UI_VALUE="${UI_OUT:-$1}"
            ;;
        checklist)
            if [ -n "$UI_OUT" ]; then
                mapfile -t UI_LIST <<< "$UI_OUT"
            fi
            ;;
    esac
    return 0
}

# --- Adaptador cli ---
# Texto puro, para quando não há dialog nem whiptail. Só b e c sozinhos navegam, para valores como "bruno" passarem;
# b só vale onde há Back. O fim da entrada (Ctrl-D) sem nada digitado cancela, como o Esc.

# Imprime o texto de um diálogo. Só as sequências \n viram quebra de linha, como no dialog/whiptail: com echo -e, um \c
# ou \033 num valor digitado (por exemplo, no resumo da confirmação) seria interpretado.
ui_cli_print() {
    printf '%s\n' "${1//\\n/$'\n'}"
}

# Fim da entrada sem nada digitado. Num terminal, é o Ctrl-D, que cancela. Sem terminal, as respostas do stdin acabaram
# antes do fim do wizard: isso não é uma ação do usuário, então o wizard sai com erro em vez de "cancelled by user".
ui_cli_eof() {
    echo
    if [ ! -t 0 ]; then
        ui_warn "A entrada acabou antes do fim do wizard: sem terminal, as respostas vêm do stdin e faltaram respostas."
        exit 1
    fi
    UI_ACTION="cancel"
}

ui_cli_menu() {
    local back="$1"
    local title="$2"
    local prompt="$3"
    shift 3

    show_banner
    echo -e "${BOLD}=== $title ===${NC}"
    ui_cli_print "$prompt"
    echo ""
    local keys=()
    local texts=()
    local current=0
    while [ $# -gt 0 ]; do
        keys+=("$1")
        texts+=("$2")
        # Como no radiolist do whiptail/dialog, o item ON é o atual e Enter vazio o mantém.
        [ "$3" = "ON" ] && current=$((${#keys[@]} - 1))
        shift 3 # key, desc, status
    done
    local i mark
    for i in "${!keys[@]}"; do
        mark="( )"
        [ "$i" -eq "$current" ] && mark="(*)"
        echo -e "  ${CYAN}[$((i+1))]${NC} $mark ${keys[i]} - ${texts[i]}"
    done
    echo ""
    local nav_prompt="Select option [1-${#keys[@]}] (Enter mantém: ${keys[current]})"
    if [ "$back" = "1" ]; then
        nav_prompt="[B] Back | [C] Cancel | $nav_prompt"
    else
        nav_prompt="[C] Cancelar | $nav_prompt"
    fi
    local choice="" idx
    while true; do
        read -rp "$nav_prompt: " choice || [ -n "$choice" ] || { ui_cli_eof; return 0; }
        case "$choice" in
            "")
                UI_ACTION="ok"
                UI_VALUE="${keys[current]}"
                return 0
                ;;
            [Bb])
                if [ "$back" = "1" ]; then
                    UI_ACTION="back"
                    return 0
                fi
                ;;
            [Cc])
                UI_ACTION="cancel"
                return 0
                ;;
            *)
                if idx=$(parse_index "$choice" "${#keys[@]}"); then
                    UI_ACTION="ok"
                    UI_VALUE="${keys[idx]}"
                    return 0
                fi
                ;;
        esac
        # %s imprime a entrada como texto: com echo -e, um \c ou \033 digitado seria interpretado.
        printf "%bOpção inválida: '%s'. Digite um número de 1 a %d.%b\n" "$YELLOW" "$choice" "${#keys[@]}" "$NC"
    done
}

# Cada entrada válida inverte os itens e mostra a lista de novo; só Enter vazio confirma, como no checklist do whiptail/dialog.
ui_cli_checklist() {
    local back="$1"
    local title="$2"
    local prompt="$3"
    shift 3

    local items=()
    local descs=()
    local statuses=()
    local idx num selections=""
    local tokens=() indexes=() invalid=() toggled=()
    local eof=0
    while [ $# -gt 0 ]; do
        items+=("$1")
        descs+=("$2")
        statuses+=("$3")
        shift 3
    done

    while true; do
        show_banner
        echo -e "${BOLD}=== $title ===${NC}"
        ui_cli_print "$prompt"
    echo ""
        echo -e "${YELLOW}Toggle options by entering numbers separated by spaces (e.g. 1 3 5), or press ENTER to confirm current:${NC}"
        if [ "$back" = "1" ]; then
            echo -e "${YELLOW}Enter 'b' to go Back, 'c' to Cancel.${NC}\n"
        else
            echo -e "${YELLOW}Digite 'c' para cancelar.${NC}\n"
        fi
        for idx in "${!items[@]}"; do
            local mark="[ ]"
            [ "${statuses[idx]}" = "ON" ] && mark="[X]"
            echo -e "  ${CYAN}[$((idx+1))]${NC} $mark ${items[idx]} - ${descs[idx]}"
        done
        echo ""
        while true; do
            # Fim da entrada sem nada digitado cancela; com um valor, vale como o valor seguido do Enter que confirma.
            if ! read -rp "Enter selection: " selections; then
                [ -n "$selections" ] || { ui_cli_eof; return 0; }
                eof=1
            fi
            indexes=()
            invalid=()
            case "$selections" in
                "")
                    break 2
                    ;;
                [Bb])
                    if [ "$back" = "1" ]; then
                        UI_ACTION="back"
                        return 0
                    fi
                    ;;
                [Cc])
                    UI_ACTION="cancel"
                    return 0
                    ;;
                *)
                    # read -a separa os números sem expansão de glob; uma entrada inválida não aplica nada.
                    read -r -a tokens <<< "$selections" || true
                    for num in "${tokens[@]}"; do
                        if idx=$(parse_index "$num" "${#items[@]}"); then
                            indexes+=("$idx")
                        else
                            invalid+=("$num")
                        fi
                    done
                    if [ "${#invalid[@]}" -eq 0 ]; then
                        break
                    fi
                    ;;
            esac
            local shown="$selections"
            if [ "${#invalid[@]}" -gt 0 ]; then
                printf -v shown '%s ' "${invalid[@]}"
                shown="${shown% }"
            fi
            printf "%bSeleção inválida: %s. Digite números de 1 a %d separados por espaço.%b\n" "$YELLOW" "$shown" "${#items[@]}" "$NC"
        done
        # Um número repetido na mesma entrada alterna o item uma vez só.
        toggled=()
        for idx in "${indexes[@]}"; do
            [ -n "${toggled[idx]:-}" ] && continue
            toggled[idx]=1
            if [ "${statuses[idx]}" = "ON" ]; then
                statuses[idx]="OFF"
            else
                statuses[idx]="ON"
            fi
        done
        [ "$eof" -eq 1 ] && break
    done

    UI_ACTION="ok"
    for idx in "${!items[@]}"; do
        [ "${statuses[idx]}" = "ON" ] && UI_LIST+=("${items[idx]}")
    done
    return 0
}

ui_cli_input() {
    local back="$1"
    local title="$2"
    local prompt="$3"
    local default_val="$4"

    show_banner
    echo -e "${BOLD}=== $title ===${NC}"
    ui_cli_print "$prompt"
    if [ "$back" = "1" ]; then
        echo -e "${YELLOW}(Enter 'b' to go Back, 'c' to Cancel)${NC}"
    else
        echo -e "${YELLOW}(Digite 'c' para cancelar)${NC}"
    fi
    local val=""
    read -rp "[$default_val]: " val || [ -n "$val" ] || { ui_cli_eof; return 0; }
    if [ "$back" = "1" ] && [[ "$val" == [Bb] ]]; then
        UI_ACTION="back"
        return 0
    fi
    case "$val" in
        [Cc])
            UI_ACTION="cancel"
            ;;
        *)
            UI_ACTION="ok"
            UI_VALUE="${val:-$default_val}"
            ;;
    esac
    return 0
}

# Só uma resposta que começa com y confirma; qualquer outra, inclusive Enter vazio, é "não".
ui_cli_yesno() {
    local back="$1"
    local title="$2"
    local prompt="$3"

    show_banner
    echo -e "${BOLD}=== $title ===${NC}"
    ui_cli_print "$prompt"
    echo ""
    local nav_prompt="(y/N, c=Cancel)"
    [ "$back" = "1" ] && nav_prompt="(y/N, b=Back, c=Cancel)"
    local ans=""
    read -rp "$nav_prompt: " ans || [ -n "$ans" ] || { ui_cli_eof; return 0; }
    if [ "$back" = "1" ] && [[ "$ans" == [Bb] ]]; then
        UI_ACTION="back"
        return 0
    fi
    case "$ans" in
        [Cc])
            UI_ACTION="cancel"
            ;;
        [Yy]*)
            UI_ACTION="ok"
            ;;
        *)
            UI_ACTION="no"
            ;;
    esac
    return 0
}

ui_cli_text() {
    local title="$2"
    local file_path="$4"

    show_banner
    echo -e "${BOLD}=== $title ===${NC}\n"
    if command -v less >/dev/null 2>&1; then
        # O less usa o Ctrl-C (por exemplo, para abortar uma busca); com o trap de INT de ui_init, o bash sairia do
        # wizard quando o less terminasse.
        trap : INT
        less "$file_path" || cat "$file_path"
        trap 'exit 130' INT
    else
        cat "$file_path"
        echo ""
        read -rp "Press Enter to continue..." _ || true
    fi
    UI_ACTION="ok"
    return 0
}

# Despacha o diálogo para o motor atual. Uso: ui_dialog <tipo> <back 0|1> <título> <texto> [argumentos do tipo].
ui_dialog() {
    UI_ACTION=""
    UI_VALUE=""
    UI_LIST=()
    while true; do
        if [ "${UI_ENGINES[0]}" = "cli" ]; then
            "ui_cli_$1" "${@:2}"
            return 0
        fi
        ui_tui "${UI_ENGINES[0]}" "$@" && return 0
        # Uma falha só no texto (por exemplo, terminal pequeno demais para a caixa) não tira do motor os outros passos,
        # que funcionam: o texto é mostrado no modo cli desta vez.
        if [ "$1" = "text" ]; then
            ui_warn "O ${UI_ENGINES[0]} não conseguiu mostrar o texto: ${UI_ERROR}"
            ui_pause
            ui_cli_text "${@:2}"
            return 0
        fi
        ui_engine_failed
    done
}

# ui_menu <back> <título> <texto> <chave> <descrição> <ON|OFF>...
ui_menu() {
    ui_dialog menu "$@"
}

# ui_checklist <back> <título> <texto> <chave> <descrição> <ON|OFF>...
ui_checklist() {
    ui_dialog checklist "$@"
}

# ui_input <back> <título> <texto> <valor padrão>
ui_input() {
    ui_dialog input "$@"
}

# ui_yesno <back> <título> <texto>
ui_yesno() {
    ui_dialog yesno "$@"
}

# ui_text <título> <arquivo>: mostra o arquivo quebrado na largura do terminal.
ui_text() {
    local title="$1"
    local file_path="$2"

    local term_lines term_cols
    term_lines=$(tput lines 2>/dev/null || echo 24)
    term_cols=$(tput cols 2>/dev/null || echo 80)

    # Use ~90% of current terminal screen height & width dynamically
    local box_lines=$(( term_lines > 6 ? term_lines - 4 : 20 ))
    local box_cols=$(( term_cols > 10 ? term_cols - 6 : 74 ))
    local wrap_width=$(( box_cols > 10 ? box_cols - 6 : 70 ))

    local tmp_file="$UI_TMP_DIR/text"
    fold -s -w "$wrap_width" "$file_path" > "$tmp_file" 2>/dev/null || cp "$file_path" "$tmp_file"
    ui_dialog text 0 "$title" "" "$tmp_file" "$box_lines" "$box_cols"
}

# --- Main Wizard Flow ---

cancel_wizard() {
    echo -e "${YELLOW}Wizard cancelled by user.${NC}"
    exit 0
}

# Monta em "screens" as telas do modo atual, na ordem em que aparecem, e em "screen_numbers" (paralelo a screens) o
# número do passo de cada uma. A lista é feita de passos: cada passo é uma ou mais telas, e os campos do modo formam um
# passo só, definido num lugar só. main guarda apenas a posição (pos) em screens: OK avança e Back volta uma posição.
# Como a lista só tem as telas que o modo mostra, o Back sempre leva à última tela vista, inclusive entre os campos do
# modo, e um modo sem campos (local) não precisa de caso especial em outra tela. A confirmação não é numerada (0).
# screens, screen_numbers, step_total e pos são variáveis locais de main: com o escopo dinâmico do bash, as atribuições
# aqui valem lá.
wizard_screens() {
    local mode_fields=""
    case "$target_mode" in
        sandbox) mode_fields="distro" ;;
        remote) mode_fields="remote_ip remote_user" ;;
        tunnel) mode_fields="remote_ip remote_user jump_ip jump_user" ;;
    esac
    local steps=("target" "$mode_fields" "profile" "tags" "dry_run")
    local step step_screens=() screen
    screens=()
    screen_numbers=()
    step_total=0
    for step in "${steps[@]}"; do
        [ -n "$step" ] || continue
        step_total=$((step_total + 1))
        read -r -a step_screens <<< "$step"
        for screen in "${step_screens[@]}"; do
            screens+=("$screen")
            screen_numbers+=("$step_total")
        done
    done
    screens+=(confirm)
    screen_numbers+=(0)
}

# Trata a ação do diálogo da tela atual: ok devolve 0 e a tela segue; back volta à tela anterior e devolve 1, para a tela
# fazer "continue"; qualquer outra ação cancela.
screen_nav() {
    case "$UI_ACTION" in
        ok) return 0 ;;
        back) pos=$((pos - 1)); return 1 ;;
        *) cancel_wizard ;;
    esac
}

# Título "Step N/T: <nome>" da tela atual (screens[pos]), com o número calculado por wizard_screens. A escolha do modo
# não mostra o total, porque ele depende do modo que ainda vai ser escolhido.
step_title() {
    local number="${screen_numbers[pos]}"
    if [ "$number" -eq 1 ]; then
        echo "Step 1: $1"
    else
        echo "Step $number/$step_total: $1"
    fi
}

main() {
    local pos=0
    local screens=()
    local screen_numbers=()
    local step_total=0
    local target_mode="local"
    local distro="void"
    local remote_ip="192.168.1.50"
    local remote_user="root"
    local jump_ip="200.200.200.200"
    local jump_user="admin"
    local selected_profile="default"
    local selected_tags_array=("devtools" "languages" "docker" "zsh" "editors" "dotfiles")
    local dry_run="no"

    ui_init

    while true; do
        wizard_screens
        case "${screens[pos]}" in
            target)
                ui_menu 0 "$(step_title "Target Selection")" \
                    "Select where you want to provision the workstation environment:" \
                    "local" "Local Machine (localhost)" "$([ "$target_mode" = "local" ] && echo ON || echo OFF)" \
                    "sandbox" "Isolated Docker Container (Sandbox)" "$([ "$target_mode" = "sandbox" ] && echo ON || echo OFF)" \
                    "remote" "Remote Server via SSH" "$([ "$target_mode" = "remote" ] && echo ON || echo OFF)" \
                    "tunnel" "Remote Server via SSH Bastion (Tunnel)" "$([ "$target_mode" = "tunnel" ] && echo ON || echo OFF)" \
                    "help" "Documentation & Usage Guide (USAGE.md)" OFF

                [ "$UI_ACTION" = "ok" ] || cancel_wizard

                if [ "$UI_VALUE" = "help" ]; then
                    ui_text "Documentation - Manual de Uso" "$REPO_DIR/docs/USAGE.md"
                    continue
                fi

                [ -n "$UI_VALUE" ] && target_mode="$UI_VALUE"
                ;;

            distro)
                ui_menu 1 "$(step_title "Sandbox Linux Distribution")" \
                    "Select Docker base distribution for Sandbox container:" \
                    "void" "Void Linux (glibc - Default)" "$([ "$distro" = "void" ] && echo ON || echo OFF)" \
                    "ubuntu" "Ubuntu 24.04 LTS" "$([ "$distro" = "ubuntu" ] && echo ON || echo OFF)" \
                    "fedora" "Fedora 44" "$([ "$distro" = "fedora" ] && echo ON || echo OFF)" \
                    "arch" "Arch Linux (rolling)" "$([ "$distro" = "arch" ] && echo ON || echo OFF)"

                screen_nav || continue
                [ -n "$UI_VALUE" ] && distro="$UI_VALUE"
                ;;

            remote_ip)
                # No tunnel, o host de destino é alcançado pelo bastion: mesmo campo, outro título.
                if [ "$target_mode" = "tunnel" ]; then
                    ui_input 1 "$(step_title "Target IP Address")" "Enter destination IP address:" "$remote_ip"
                else
                    ui_input 1 "$(step_title "Remote SSH Host")" "Enter target IP address:" "$remote_ip"
                fi
                screen_nav || continue
                [ -n "$UI_VALUE" ] && remote_ip="$UI_VALUE"
                ;;

            remote_user)
                if [ "$target_mode" = "tunnel" ]; then
                    ui_input 1 "$(step_title "Target Username")" "Enter SSH username on target host:" "$remote_user"
                else
                    ui_input 1 "$(step_title "Remote SSH User")" "Enter SSH username:" "$remote_user"
                fi
                screen_nav || continue
                [ -n "$UI_VALUE" ] && remote_user="$UI_VALUE"
                ;;

            jump_ip)
                ui_input 1 "$(step_title "Bastion Jump IP")" "Enter Jump Box IP address:" "$jump_ip"
                screen_nav || continue
                [ -n "$UI_VALUE" ] && jump_ip="$UI_VALUE"
                ;;

            jump_user)
                ui_input 1 "$(step_title "Bastion Username")" "Enter SSH username on Jump Box:" "$jump_user"
                screen_nav || continue
                [ -n "$UI_VALUE" ] && jump_user="$UI_VALUE"
                ;;

            profile)
                local profiles=()
                for pfile in "$REPO_DIR"/profiles/*.yml; do
                    local pname
                    pname=$(basename "$pfile" .yml)
                    [ "$pname" != "local.sample" ] && profiles+=("$pname")
                done

                local profile_choices=()
                for p in "${profiles[@]}"; do
                    local status="OFF"
                    [ "$p" = "$selected_profile" ] && status="ON"
                    local desc="Profile configuration ($p.yml)"
                    [ "$p" = "default" ] && desc="Standard base workstation profile"
                    [ "$p" = "local" ] && desc="Personal local overrides profile"
                    profile_choices+=("$p" "$desc" "$status")
                done

                ui_menu 1 "$(step_title "Profile Selection")" \
                    "Select configuration profile to apply:" \
                    "${profile_choices[@]}"

                screen_nav || continue
                [ -n "$UI_VALUE" ] && selected_profile="$UI_VALUE"
                ;;

            tags)
                local available_tags=(
                    "devtools" "Base CLI tools (git, tmux, fzf, stow, btop)"
                    "languages" "All programming languages (Python, Node, Rust, Go)"
                    "python" "Python toolchain (UV + Pipx)"
                    "node" "Node.js & NPM package manager"
                    "rust" "Rustup & Cargo toolchain"
                    "go" "Golang compiler & environment"
                    "docker" "Docker engine & user permissions"
                    "zsh" "Zsh shell, Oh-My-Zsh & P10k theme"
                    "editors" "Neovim, lldb & clipboard support"
                    "ui" "Opt-in Sway WM, Waybar & Nerd Fonts"
                    "dotfiles" "Dotfiles symlinking via GNU Stow"
                )

                local tag_choices=()
                for ((i=0; i<${#available_tags[@]}; i+=2)); do
                    local tag_name="${available_tags[i]}"
                    local tag_desc="${available_tags[i+1]}"
                    local status="OFF"
                    for st in "${selected_tags_array[@]}"; do
                        if [ "$st" = "$tag_name" ]; then
                            status="ON"
                            break
                        fi
                    done
                    tag_choices+=("$tag_name" "$tag_desc" "$status")
                done

                ui_checklist 1 "$(step_title "Component Selection")" \
                    "Select components to install/configure (Space to toggle, Enter to confirm):" \
                    "${tag_choices[@]}"

                screen_nav || continue
                selected_tags_array=("${UI_LIST[@]}")
                ;;

            dry_run)
                ui_yesno 1 "$(step_title "Simulation (Dry-Run)")" "Do you want to run in simulation mode (--check --diff) without modifying the system?"
                case "$UI_ACTION" in
                    ok) dry_run="yes" ;;
                    no) dry_run="no" ;;
                    *) screen_nav || continue ;;
                esac
                ;;

            confirm)
                local formatted_tags
                if [ "${#selected_tags_array[@]}" -eq 0 ]; then
                    formatted_tags="all"
                else
                    # O IFS="," fica num subshell: um "local IFS" valeria para o resto de main, inclusive depois de Back.
                    formatted_tags=$(IFS=","; echo "${selected_tags_array[*]}")
                fi

                local run_args=()
                run_args+=("$target_mode")
                # Sempre --opção=valor: um valor digitado que começa com "-" chega à validação do script, em vez de ser
                # lido como outra opção ("a opção --ip exige um valor").
                run_args+=("--profile=$selected_profile")
                run_args+=("--tags=$formatted_tags")

                case "$target_mode" in
                    sandbox) run_args+=("--distro=$distro") ;;
                    remote)  run_args+=("--ip=$remote_ip" "--user=$remote_user") ;;
                    tunnel)  run_args+=("--ip=$remote_ip" "--user=$remote_user" "--jump-ip=$jump_ip" "--jump-user=$jump_user") ;;
                esac

                [ "$dry_run" = "yes" ] && run_args+=(--dry-run)

                # O comando mostrado pode ser copiado e colado: o caminho é o pelo qual o usuário chamou o
                # scripts/workstation.sh ou o atalho ./workstation.sh da raiz (WORKSTATION_PROG, que o
                # scripts/workstation.sh repassa) ou, com o wizard chamado direto, o caminho absoluto.
                local run_cmd
                shell_join run_cmd "${WORKSTATION_PROG:-$REPO_DIR/scripts/workstation.sh}" "${run_args[@]}"

                local summary_text="Provisioning Configuration Summary:\n"
                summary_text+="\n - Execution Target: ${target_mode}"
                [ "$target_mode" = "sandbox" ] && summary_text+=" (Distro: ${distro})"
                [ "$target_mode" = "remote" ] && summary_text+=" (Host: ${remote_user}@${remote_ip})"
                [ "$target_mode" = "tunnel" ] && summary_text+=" (Target: ${remote_user}@${remote_ip} via ${jump_user}@${jump_ip})"
                summary_text+="\n - Profile: ${selected_profile}"
                summary_text+="\n - Selected Tags: ${formatted_tags}"
                summary_text+="\n - Simulation Mode: $([ "$dry_run" = "yes" ] && echo "Yes (Dry Run)" || echo "No (Real execution)")"
                summary_text+="\n\nCommand to execute:\n ${run_cmd}"

                ui_yesno 1 "Confirmation" "$summary_text\n\nDo you want to proceed with provisioning now?"
                case "$UI_ACTION" in
                    ok)
                        show_banner
                        echo -e "${GREEN}${BOLD}>> Executing: ${run_cmd}${NC}\n"
                        bash "$REPO_DIR/scripts/workstation.sh" "${run_args[@]}"
                        break
                        ;;
                    back)
                        screen_nav || continue
                        ;;
                    *)
                        echo -e "\n${YELLOW}Provisioning cancelled by user.${NC}"
                        exit 0
                        ;;
                esac
                ;;

            *)
                # Uma tela da lista sem case seria pulada em silêncio, e o Back nunca passaria dela.
                ui_fatal "Tela sem tratamento no wizard: ${screens[pos]}"
                ;;
        esac
        pos=$((pos + 1))
    done
}

main "$@"

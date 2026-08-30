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
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- Root Dir Resolution ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# --- Detection of TUI Tool ---
if [ -z "${TUI_ENGINE:-}" ]; then
    if command -v whiptail >/dev/null 2>&1; then
        TUI_ENGINE="whiptail"
    elif command -v dialog >/dev/null 2>&1; then
        TUI_ENGINE="dialog"
    else
        TUI_ENGINE="cli"
    fi
fi

show_banner() {
    clear
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

tui_menu() {
    local show_back="$1"
    local title="$2"
    local prompt="$3"
    shift 3

    local out=""
    local rc=0
    local extra_args=()
    [ "$show_back" = "1" ] && extra_args+=(--extra-button --extra-label "Back")

    if [ "$TUI_ENGINE" = "whiptail" ]; then
        out=$(whiptail "${extra_args[@]}" --backtitle "Workstation Ansible" --title "$title" --radiolist "$prompt" 18 70 8 "$@" 3>&1 1>&2 2>&3) || rc=$?
    elif [ "$TUI_ENGINE" = "dialog" ]; then
        out=$(dialog --stdout "${extra_args[@]}" --backtitle "Workstation Ansible" --title "$title" --radiolist "$prompt" 18 70 8 "$@") || rc=$?
    else
        show_banner
        echo -e "${BOLD}=== $title ===${NC}"
        echo -e "$prompt\n"
        local keys=()
        local texts=()
        local i=1
        while [ $# -gt 0 ]; do
            keys+=("$1")
            texts+=("$2")
            shift 3 # key, desc, status
            echo -e "  ${CYAN}[$i]${NC} ${keys[$((i-1))]} - ${texts[$((i-1))]}"
            ((i++))
        done
        echo ""
        local nav_prompt="Select option [1-$((i-1))]"
        [ "$show_back" = "1" ] && nav_prompt="[B] Back | [C] Cancel | $nav_prompt"
        read -rp "$nav_prompt: " choice
        case "$choice" in
            [Bb]*)
                if [ "$show_back" = "1" ]; then
                    return 3
                fi
                ;;
            [Cc]*)
                return 1
                ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$i" ]; then
                    out="${keys[$((choice-1))]}"
                else
                    out="${keys[0]}"
                fi
                ;;
        esac
    fi
    echo "$out"
    return $rc
}

tui_checklist() {
    local show_back="$1"
    local title="$2"
    local prompt="$3"
    shift 3

    local out=""
    local rc=0
    local extra_args=()
    [ "$show_back" = "1" ] && extra_args+=(--extra-button --extra-label "Back")

    if [ "$TUI_ENGINE" = "whiptail" ]; then
        out=$(whiptail "${extra_args[@]}" --backtitle "Workstation Ansible" --title "$title" --checklist "$prompt" 22 75 12 "$@" 3>&1 1>&2 2>&3) || rc=$?
    elif [ "$TUI_ENGINE" = "dialog" ]; then
        out=$(dialog --stdout "${extra_args[@]}" --backtitle "Workstation Ansible" --title "$title" --checklist "$prompt" 22 75 12 "$@") || rc=$?
    else
        show_banner
        echo -e "${BOLD}=== $title ===${NC}"
        echo -e "$prompt\n"
        local items=()
        local descs=()
        local statuses=()
        while [ $# -gt 0 ]; do
            items+=("$1")
            descs+=("$2")
            statuses+=("$3")
            shift 3
        done

        echo -e "${YELLOW}Toggle options by entering numbers separated by spaces (e.g. 1 3 5), or press ENTER to confirm current:${NC}"
        [ "$show_back" = "1" ] && echo -e "${YELLOW}Enter 'b' to go Back, 'c' to Cancel.${NC}\n"
        for idx in "${!items[@]}"; do
            local mark="[ ]"
            [ "${statuses[$idx]}" = "ON" ] && mark="[X]"
            echo -e "  ${CYAN}[$((idx+1))]${NC} $mark ${items[$idx]} - ${descs[$idx]}"
        done
        echo ""
        read -rp "Enter selection: " selections
        case "$selections" in
            [Bb]*)
                if [ "$show_back" = "1" ]; then
                    return 3
                fi
                ;;
            [Cc]*)
                return 1
                ;;
            *)
                if [ -n "$selections" ]; then
                    for num in $selections; do
                        if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#items[@]}" ]; then
                            local idx=$((num-1))
                            if [ "${statuses[$idx]}" = "ON" ]; then
                                statuses[$idx]="OFF"
                            else
                                statuses[$idx]="ON"
                            fi
                        fi
                    done
                fi
                ;;
        esac
        local selected=()
        for idx in "${!items[@]}"; do
            [ "${statuses[$idx]}" = "ON" ] && selected+=("${items[$idx]}")
        done
        out="${selected[*]}"
    fi
    echo "$out"
    return $rc
}

tui_inputbox() {
    local show_back="$1"
    local title="$2"
    local prompt="$3"
    local default_val="$4"

    local out=""
    local rc=0
    local extra_args=()
    [ "$show_back" = "1" ] && extra_args+=(--extra-button --extra-label "Back")

    if [ "$TUI_ENGINE" = "whiptail" ]; then
        out=$(whiptail "${extra_args[@]}" --backtitle "Workstation Ansible" --title "$title" --inputbox "$prompt" 12 65 "$default_val" 3>&1 1>&2 2>&3) || rc=$?
    elif [ "$TUI_ENGINE" = "dialog" ]; then
        out=$(dialog --stdout "${extra_args[@]}" --backtitle "Workstation Ansible" --title "$title" --inputbox "$prompt" 12 65 "$default_val") || rc=$?
    else
        show_banner
        echo -e "${BOLD}=== $title ===${NC}"
        echo -e "$prompt"
        [ "$show_back" = "1" ] && echo -e "${YELLOW}(Enter 'b' to go Back, 'c' to Cancel)${NC}"
        read -rp "[$default_val]: " val
        case "$val" in
            [Bb]*)
                if [ "$show_back" = "1" ]; then
                    return 3
                fi
                ;;
            [Cc]*)
                return 1
                ;;
            *)
                out="${val:-$default_val}"
                ;;
        esac
    fi
    echo "${out:-$default_val}"
    return $rc
}

tui_yesno() {
    local show_back="$1"
    local title="$2"
    local prompt="$3"

    local extra_args=()
    [ "$show_back" = "1" ] && extra_args+=(--extra-button --extra-label "Back")

    if [ "$TUI_ENGINE" = "whiptail" ]; then
        whiptail "${extra_args[@]}" --backtitle "Workstation Ansible" --title "$title" --yesno "$prompt" 20 75
    elif [ "$TUI_ENGINE" = "dialog" ]; then
        dialog "${extra_args[@]}" --backtitle "Workstation Ansible" --title "$title" --yesno "$prompt" 20 75
    else
        show_banner
        echo -e "${BOLD}=== $title ===${NC}"
        local nav_prompt="$prompt (y/N)"
        [ "$show_back" = "1" ] && nav_prompt="$prompt (y/N/b=Back/c=Cancel)"
        read -rp "$nav_prompt: " ans
        case "$ans" in
            [Bb]*)
                if [ "$show_back" = "1" ]; then
                    return 3
                fi
                ;;
            [Cc]*)
                return 1
                ;;
            [Yy]*)
                return 0
                ;;
            *)
                return 1
                ;;
        esac
    fi
}

tui_textbox() {
    local title="$1"
    local file_path="$2"

    local term_lines term_cols
    term_lines=$(tput lines 2>/dev/null || echo 24)
    term_cols=$(tput cols 2>/dev/null || echo 80)

    # Use ~90% of current terminal screen height & width dynamically
    local box_lines=$(( term_lines > 6 ? term_lines - 4 : 20 ))
    local box_cols=$(( term_cols > 10 ? term_cols - 6 : 74 ))
    local wrap_width=$(( box_cols > 10 ? box_cols - 6 : 70 ))

    local tmp_file
    tmp_file=$(mktemp)
    fold -s -w "$wrap_width" "$file_path" > "$tmp_file" 2>/dev/null || cp "$file_path" "$tmp_file"

    if [ "$TUI_ENGINE" = "whiptail" ]; then
        whiptail --backtitle "Workstation Ansible" --title "$title" --scrolltext --textbox "$tmp_file" "$box_lines" "$box_cols" || true
    elif [ "$TUI_ENGINE" = "dialog" ]; then
        dialog --backtitle "Workstation Ansible" --title "$title" --textbox "$tmp_file" "$box_lines" "$box_cols" || true
    else
        show_banner
        echo -e "${BOLD}=== $title ===${NC}\n"
        if command -v less >/dev/null 2>&1; then
            less "$tmp_file" || cat "$tmp_file"
        else
            cat "$tmp_file"
            echo ""
            read -rp "Press Enter to continue..." _
        fi
    fi

    rm -f "$tmp_file"
}

# --- Main Wizard Flow ---

main() {
    local step=1
    local target_mode="local"
    local distro="void"
    local remote_ip="192.168.1.50"
    local remote_user="root"
    local jump_ip="200.200.200.200"
    local jump_user="admin"
    local selected_profile="default"
    local selected_tags_array=("devtools" "languages" "docker" "zsh" "editors" "dotfiles")
    local dry_run="no"

    while true; do
        case "$step" in
            1) # Step 1: Target Selection
                local res=""
                local rc=0
                res=$(tui_menu 0 "Step 1/5: Target Selection" \
                    "Select where you want to provision the workstation environment:" \
                    "local" "Local Machine (localhost)" "$([ "$target_mode" = "local" ] && echo ON || echo OFF)" \
                    "sandbox" "Isolated Docker Container (Sandbox)" "$([ "$target_mode" = "sandbox" ] && echo ON || echo OFF)" \
                    "remote" "Remote Server via SSH" "$([ "$target_mode" = "remote" ] && echo ON || echo OFF)" \
                    "tunnel" "Remote Server via SSH Bastion (Tunnel)" "$([ "$target_mode" = "tunnel" ] && echo ON || echo OFF)" \
                    "help" "Documentation & Usage Guide (USAGE.md)" OFF) || rc=$?

                if [ "$rc" -ne 0 ]; then
                    echo -e "${YELLOW}Wizard cancelled by user.${NC}"
                    exit 0
                fi

                if [ "$res" = "help" ]; then
                    tui_textbox "Documentation - Manual de Uso" "$REPO_DIR/docs/USAGE.md"
                    step=1
                    continue
                fi

                [ -n "$res" ] && target_mode="$res"
                step=2
                ;;

            2) # Step 2: Mode-Specific Parameters
                case "$target_mode" in
                    sandbox)
                        local res=""
                        local rc=0
                        res=$(tui_menu 1 "Step 2/5: Sandbox Linux Distribution" \
                            "Select Docker base distribution for Sandbox container:" \
                            "void" "Void Linux (glibc - Default)" "$([ "$distro" = "void" ] && echo ON || echo OFF)" \
                            "ubuntu" "Ubuntu 22.04 LTS" "$([ "$distro" = "ubuntu" ] && echo ON || echo OFF)") || rc=$?

                        if [ "$rc" -eq 3 ]; then
                            step=1
                            continue
                        elif [ "$rc" -ne 0 ]; then
                            echo -e "${YELLOW}Wizard cancelled by user.${NC}"
                            exit 0
                        fi
                        [ -n "$res" ] && distro="$res"
                        ;;

                    remote)
                        local res_ip="" res_user="" rc_ip=0 rc_user=0
                        res_ip=$(tui_inputbox 1 "Step 2/5: Remote SSH Host" "Enter target IP address:" "$remote_ip") || rc_ip=$?
                        if [ "$rc_ip" -eq 3 ]; then
                            step=1
                            continue
                        elif [ "$rc_ip" -ne 0 ]; then
                            echo -e "${YELLOW}Wizard cancelled by user.${NC}"
                            exit 0
                        fi
                        [ -n "$res_ip" ] && remote_ip="$res_ip"

                        res_user=$(tui_inputbox 1 "Step 2/5: Remote SSH User" "Enter SSH username:" "$remote_user") || rc_user=$?
                        if [ "$rc_user" -eq 3 ]; then
                            continue
                        elif [ "$rc_user" -ne 0 ]; then
                            echo -e "${YELLOW}Wizard cancelled by user.${NC}"
                            exit 0
                        fi
                        [ -n "$res_user" ] && remote_user="$res_user"
                        ;;

                    tunnel)
                        local res_ip="" res_user="" res_jip="" res_juser="" rc=0
                        res_ip=$(tui_inputbox 1 "Step 2/5: Target IP Address" "Enter destination IP address:" "$remote_ip") || rc=$?
                        if [ "$rc" -eq 3 ]; then step=1; continue; fi
                        [ "$rc" -ne 0 ] && { echo -e "${YELLOW}Wizard cancelled by user.${NC}"; exit 0; }
                        [ -n "$res_ip" ] && remote_ip="$res_ip"

                        res_user=$(tui_inputbox 1 "Step 2/5: Target Username" "Enter SSH username on target host:" "$remote_user") || rc=$?
                        if [ "$rc" -eq 3 ]; then continue; fi
                        [ "$rc" -ne 0 ] && { echo -e "${YELLOW}Wizard cancelled by user.${NC}"; exit 0; }
                        [ -n "$res_user" ] && remote_user="$res_user"

                        res_jip=$(tui_inputbox 1 "Step 2/5: Bastion Jump IP" "Enter Jump Box IP address:" "$jump_ip") || rc=$?
                        if [ "$rc" -eq 3 ]; then continue; fi
                        [ "$rc" -ne 0 ] && { echo -e "${YELLOW}Wizard cancelled by user.${NC}"; exit 0; }
                        [ -n "$res_jip" ] && jump_ip="$res_jip"

                        res_juser=$(tui_inputbox 1 "Step 2/5: Bastion Username" "Enter SSH username on Jump Box:" "$jump_user") || rc=$?
                        if [ "$rc" -eq 3 ]; then continue; fi
                        [ "$rc" -ne 0 ] && { echo -e "${YELLOW}Wizard cancelled by user.${NC}"; exit 0; }
                        [ -n "$res_juser" ] && jump_user="$res_juser"
                        ;;
                esac
                step=3
                ;;

            3) # Step 3: Profile Selection
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

                local res="" rc=0
                res=$(tui_menu 1 "Step 3/5: Profile Selection" \
                    "Select configuration profile to apply:" \
                    "${profile_choices[@]}") || rc=$?

                if [ "$rc" -eq 3 ]; then
                    step=2
                    continue
                elif [ "$rc" -ne 0 ]; then
                    echo -e "${YELLOW}Wizard cancelled by user.${NC}"
                    exit 0
                fi
                [ -n "$res" ] && selected_profile="$res"
                step=4
                ;;

            4) # Step 4: Component Checklist
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

                local res="" rc=0
                res=$(tui_checklist 1 "Step 4/5: Component Selection" \
                    "Select components to install/configure (Space to toggle, Enter to confirm):" \
                    "${tag_choices[@]}") || rc=$?

                if [ "$rc" -eq 3 ]; then
                    step=3
                    continue
                elif [ "$rc" -ne 0 ]; then
                    echo -e "${YELLOW}Wizard cancelled by user.${NC}"
                    exit 0
                fi

                # Update selected_tags_array cleanly without eval
                selected_tags_array=()
                if [ -n "$res" ]; then
                    local cleaned_res
                    cleaned_res=$(echo "$res" | tr -d '"' | tr -d "'")
                    read -r -a selected_tags_array <<< "$cleaned_res" || true
                fi
                step=5
                ;;

            5) # Step 5: Dry-Run Mode Toggle
                local rc=0
                if tui_yesno 1 "Step 5/5: Simulation (Dry-Run)" "Do you want to run in simulation mode (--check --diff) without modifying the system?"; then
                    dry_run="yes"
                else
                    rc=$?
                    if [ "$rc" -eq 3 ]; then
                        step=4
                        continue
                    elif [ "$rc" -eq 1 ]; then
                        dry_run="no"
                    else
                        echo -e "${YELLOW}Wizard cancelled by user.${NC}"
                        exit 0
                    fi
                fi
                step=6
                ;;

            6) # Step 6: Summary & Confirmation
                local formatted_tags
                if [ "${#selected_tags_array[@]}" -eq 0 ]; then
                    formatted_tags="all"
                else
                    local IFS=","
                    formatted_tags="${selected_tags_array[*]}"
                fi

                local make_args=()
                make_args+=("$target_mode")
                make_args+=("PROFILE=$selected_profile")
                make_args+=("TAGS=$formatted_tags")

                case "$target_mode" in
                    sandbox) make_args+=("DISTRO=$distro") ;;
                    remote)  make_args+=("IP=$remote_ip" "USER=$remote_user") ;;
                    tunnel)  make_args+=("IP=$remote_ip" "USER=$remote_user" "JUMP_IP=$jump_ip" "JUMP_USER=$jump_user") ;;
                esac

                [ "$dry_run" = "yes" ] && make_args+=("DRY=1")

                local summary_text="Provisioning Configuration Summary:\n"
                summary_text+="\n - Execution Target: ${target_mode}"
                [ "$target_mode" = "sandbox" ] && summary_text+=" (Distro: ${distro})"
                [ "$target_mode" = "remote" ] && summary_text+=" (Host: ${remote_user}@${remote_ip})"
                [ "$target_mode" = "tunnel" ] && summary_text+=" (Target: ${remote_user}@${remote_ip} via ${jump_user}@${jump_ip})"
                summary_text+="\n - Profile: ${selected_profile}"
                summary_text+="\n - Selected Tags: ${formatted_tags}"
                summary_text+="\n - Simulation Mode: $([ "$dry_run" = "yes" ] && echo "Yes (Dry Run)" || echo "No (Real execution)")"
                summary_text+="\n\nCommand to execute:\n make ${make_args[*]}"

                local rc=0
                if tui_yesno 1 "Confirmation" "$summary_text\n\nDo you want to proceed with provisioning now?"; then
                    show_banner
                    echo -e "${GREEN}${BOLD}>> Executing: make ${make_args[*]}${NC}\n"
                    cd "$REPO_DIR"
                    make "${make_args[@]}"
                    break
                else
                    rc=$?
                    if [ "$rc" -eq 3 ]; then
                        step=5
                        continue
                    else
                        echo -e "\n${YELLOW}Provisioning cancelled by user.${NC}"
                        exit 0
                    fi
                fi
                ;;
        esac
    done
}

main "$@"

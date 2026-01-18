# --- Variáveis Padrão ---
PLAYBOOK := playbooks/site.yml
USER ?= $(USER)
TAGS ?= all

# --- Configuração de Cores ---
GREEN  := $(shell tput -Txterm setaf 2)
YELLOW := $(shell tput -Txterm setaf 3)
RESET  := $(shell tput -Txterm sgr0)

# --- Argumentos e Flags ---
ANS_TAGS := --tags "$(TAGS)"
ANS_EXTRA_FLAGS :=

# Lógica para DRY RUN (Simulação)
# Uso: make local DRY=1
ifdef DRY
	ANS_EXTRA_FLAGS += --check --diff
	MSG_DRY := [DRY RUN MODE]
else
	MSG_DRY :=
endif

.PHONY: help local remote tunnel lint deps

help:
	@echo ''
	@echo '${YELLOW}Workstation Ansible - Comandos Disponíveis:${RESET}'
	@echo ''
	@echo '  ${GREEN}make local [DRY=1] [TAGS=...]${RESET}      Provisiona localhost.'
	@echo '  ${GREEN}make remote IP=... [DRY=1] [TAGS=...]${RESET}  Provisiona remoto.'
	@echo '  ${GREEN}make tunnel IP=... JUMP_IP=...${RESET}        Provisiona via Bastion.'
	@echo '  ${GREEN}make deps${RESET}                             Instala roles do Galaxy.'
	@echo '  ${GREEN}make lint${RESET}                             Verifica sintaxe.'
	@echo ''
	@echo '  ${YELLOW}Exemplos de Uso:${RESET}'
	@echo '    make local DRY=1                 (Simulação completa)'
	@echo '    make local TAGS=zsh              (Apenas ZSH)'
	@echo '    make remote IP=192.168.1.50 TAGS=docker,dotfiles'
	@echo ''
	@echo '  ${YELLOW}Tags Disponíveis:${RESET}'
	@echo '    ${GREEN}devtools${RESET}   Pacotes base (git, curl, tmux)'
	@echo '    ${GREEN}languages${RESET}  Node.js (Volta), Python (UV), Rust'
	@echo '    ${GREEN}docker${RESET}     Docker Engine e Compose'
	@echo '    ${GREEN}zsh${RESET}        Shell, Oh-My-Zsh, Powerlevel10k'
	@echo '    ${GREEN}ui${RESET}         Sway, Waybar, Nerd Fonts (Visuals)'
	@echo '    ${GREEN}dotfiles${RESET}   Links simbólicos (Stow)'
	@echo ''

deps:
	@echo "${GREEN}Instalando dependências do Ansible...${RESET}"
	ansible-galaxy install -r requirements.yml 2>/dev/null || echo "Nenhum requirements.yml encontrado, ignorando."

lint:
	@echo "${GREEN}Rodando Ansible Lint...${RESET}"
	ansible-lint playbooks/*.yml

local:
	@echo "${GREEN}Iniciando provisionamento LOCAL $(MSG_DRY) [Tags: $(TAGS)]...${RESET}"
	ansible-playbook $(PLAYBOOK) \
		-i "localhost," \
		-c local \
		$(ANS_TAGS) \
		$(ANS_EXTRA_FLAGS) \
		$(ARGS) \
		-K

remote:
ifndef IP
	$(error IP não definido. Use: make remote IP=x.x.x.x)
endif
	@echo "${GREEN}Iniciando provisionamento em $(IP) $(MSG_DRY) [Tags: $(TAGS)]...${RESET}"
	ansible-playbook $(PLAYBOOK) \
		-i "$(IP)," \
		-u $(USER) \
		$(ANS_TAGS) \
		$(ANS_EXTRA_FLAGS) \
		-K

tunnel:
ifndef IP
	$(error IP (destino) não definido.)
endif
ifndef JUMP_IP
	$(error JUMP_IP (bastion) não definido.)
endif
	@echo "${GREEN}Iniciando provisionamento Tunnel $(MSG_DRY) [Tags: $(TAGS)]...${RESET}"
	ansible-playbook $(PLAYBOOK) \
		-i "$(IP)," \
		-u $(USER) \
		--ssh-common-args='-o ProxyCommand="ssh -W %h:%p -q $(JUMP_USER)@$(JUMP_IP)"' \
		$(ANS_TAGS) \
		$(ANS_EXTRA_FLAGS) \
		-K

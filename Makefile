# --- Variáveis Principais ---
PLAYBOOK  := playbooks/site.yml
PROFILE   ?= default
TAGS      ?= all
USER      ?= $(shell whoami)
IP        ?= localhost

# --- Cores para Output ---
GREEN  := $(shell tput -Txterm setaf 2)
YELLOW := $(shell tput -Txterm setaf 3)
RESET  := $(shell tput -Txterm sgr0)

# --- Montagem dos Argumentos do Ansible ---
ANS_TAGS        := --tags "$(TAGS)"
ANS_EXTRA_VARS  := -e "profile=$(PROFILE)"
ANS_FLAGS       := -K $(ANS_TAGS) $(ANS_EXTRA_VARS)

# --- Modo Dry Run (Simulação) ---
# Uso: make local DRY=1
ifdef DRY
	ANS_FLAGS += --check --diff
	MSG_MODE  := [DRY RUN]
else
	MSG_MODE  := [EXECUÇÃO]
endif

# --- Comando Base ---
ANSIBLE_CMD = ansible-playbook $(PLAYBOOK) $(ANS_FLAGS) $(ARGS)

.PHONY: help help-docs local remote tunnel deps lint

# --- Targets ---

help:
	@echo ''
	@echo '${YELLOW}Workstation Ansible CLI${RESET}'
	@echo ''
	@echo '  ${GREEN}make local${RESET}       Provisiona esta máquina (localhost).'
	@echo '  ${GREEN}make remote${RESET}      Provisiona servidor remoto via SSH.'
	@echo '  ${GREEN}make tunnel${RESET}      Provisiona via Bastion Host.'
	@echo '  ${GREEN}make help-docs${RESET}   Exibe documentação detalhada e exemplos.'

	@echo ''
	@echo '  ${YELLOW}Opções Comuns:${RESET}'
	@echo '    TAGS=...       (zsh, docker, dotfiles, devtools, languages)'
	@echo '    PROFILE=...    (default, minimal - ou seu custom)'
	@echo '    DRY=1          (Modo simulação)'


help-docs:
	@cat docs/USAGE.md
	@echo ''

deps:
	@echo "${GREEN}>> Instalando dependências do Galaxy...${RESET}"
	ansible-galaxy install -r requirements.yml 2>/dev/null || echo ">> Nenhum requirements.yml encontrado."

lint:
	@echo "${GREEN}>> Executando Ansible Lint...${RESET}"
	ansible-lint playbooks/*.yml

local:
	@echo "${GREEN}>> Iniciando $(MSG_MODE) LOCAL [Tags: $(TAGS)]...${RESET}"
	$(ANSIBLE_CMD) -i "localhost," -c local

remote:
ifndef IP
	$(error Defina o IP de destino: make remote IP=x.x.x.x)
endif
	@echo "${GREEN}>> Iniciando $(MSG_MODE) REMOTE em $(IP) [Tags: $(TAGS)]...${RESET}"
	$(ANSIBLE_CMD) -i "$(IP)," -u $(USER)

tunnel:
ifndef IP
	$(error Defina o IP de destino: IP=x.x.x.x)
endif
ifndef JUMP_IP
	$(error Defina o IP do Bastion: JUMP_IP=x.x.x.x)
endif
	@echo "${GREEN}>> Iniciando $(MSG_MODE) TUNNEL via $(JUMP_IP) para $(IP)...${RESET}"
	$(ANSIBLE_CMD) -i "$(IP)," -u $(USER) \
		--ssh-common-args='-o ProxyCommand="ssh -W %h:%p -q $(JUMP_USER)@$(JUMP_IP)"'
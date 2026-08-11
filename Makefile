# --- Forçar Cores e Output em Tempo Real ---
export ANSIBLE_FORCE_COLOR = 1
export PYTHONUNBUFFERED = 1

# --- Variáveis Principais ---
PLAYBOOK  := playbooks/site.yml
PROFILE   ?= default
TAGS      ?= all
USER      ?= $(shell whoami)
IP        ?= localhost

# --- Variáveis para Sandbox ---
DISTRO            ?= void
SANDBOX_IMAGE     := workstation-sandbox-image-$(DISTRO)
SANDBOX_CONTAINER := workstation-sandbox-$(DISTRO)

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

.PHONY: help help-docs local remote tunnel deps lint sandbox sandbox-shell sandbox-clean

# --- Targets ---

help:
	@echo ''
	@echo '${YELLOW}Workstation Ansible CLI${RESET}'
	@echo ''
	@echo '  ${GREEN}make local${RESET}          Provisiona esta máquina (localhost).'
	@echo '  ${GREEN}make remote${RESET}         Provisiona servidor remoto via SSH.'
	@echo '  ${GREEN}make tunnel${RESET}         Provisiona via Bastion Host.'
	@echo '  ${GREEN}make sandbox${RESET}        Provisiona em container Docker isolado (Void/Ubuntu).'
	@echo '  ${GREEN}make sandbox-shell${RESET}  Acessa o terminal interativo do container sandbox.'
	@echo '  ${GREEN}make sandbox-clean${RESET}  Para e remove o container sandbox.'
	@echo '  ${GREEN}make help-docs${RESET}      Exibe documentação detalhada e exemplos.'
	@echo ''
	@echo '  ${YELLOW}Opções Comuns:${RESET}'
	@echo '    TAGS=...          (zsh, docker, dotfiles, devtools, languages, node, python, rust, go)'
	@echo '    DISTRO=...        (void, ubuntu - default: void)'
	@echo '    PROFILE=...       (default, local)'
	@echo '    DRY=1             (Modo simulação)'

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

# --- Pipeline de Testes Sandbox (Docker) ---

sandbox:
	@echo "${GREEN}>> Preparando ambiente Sandbox Docker (Distro: $(DISTRO))...${RESET}"
	@if [ ! -f tests/sandbox/Dockerfile.$(DISTRO) ]; then \
		echo "${YELLOW}Erro: Dockerfile para a distro '$(DISTRO)' não encontrado em tests/sandbox/Dockerfile.$(DISTRO)${RESET}"; \
		exit 1; \
	fi
	@echo "${GREEN}>> Construindo imagem $(SANDBOX_IMAGE)...${RESET}"
	docker build -t $(SANDBOX_IMAGE) -f tests/sandbox/Dockerfile.$(DISTRO) tests/sandbox/
	@echo "${GREEN}>> Garantindo que o container $(SANDBOX_CONTAINER) esteja rodando...${RESET}"
	@docker rm -f $(SANDBOX_CONTAINER) 2>/dev/null || true
	docker run -d --name $(SANDBOX_CONTAINER) $(SANDBOX_IMAGE)
	@echo "${GREEN}>> Executando Ansible via Docker Connection no container $(SANDBOX_CONTAINER) [Tags: $(TAGS)]...${RESET}"
	ansible-playbook $(PLAYBOOK) --tags "$(TAGS)" -e "profile=$(PROFILE)" $(ARGS) -i "$(SANDBOX_CONTAINER)," -c docker -u dev
	@echo ''
	@echo '${GREEN}======================================================================${RESET}'
	@echo '${GREEN} SUCCESS: Provisionamento Sandbox concluído!${RESET}'
	@echo '${YELLOW} Para entrar no container sandbox e testar a instalação:${RESET}'
	@echo '   ${GREEN}make sandbox-shell DISTRO=$(DISTRO)${RESET}'
	@echo '   ou: ${GREEN}docker exec -it $(SANDBOX_CONTAINER) /bin/bash${RESET}'
	@echo '${YELLOW} Para remover o container sandbox:${RESET}'
	@echo '   ${GREEN}make sandbox-clean DISTRO=$(DISTRO)${RESET}'
	@echo '${GREEN}======================================================================${RESET}'

sandbox-shell:
	@echo "${GREEN}>> Entrando no container sandbox ($(SANDBOX_CONTAINER))...${RESET}"
	docker exec -it $(SANDBOX_CONTAINER) /bin/bash

sandbox-clean:
	@echo "${GREEN}>> Parando e removendo container sandbox ($(SANDBOX_CONTAINER))...${RESET}"
	docker rm -f $(SANDBOX_CONTAINER) 2>/dev/null || true
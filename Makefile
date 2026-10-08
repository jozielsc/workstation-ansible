# --- Forçar Cores e Output em Tempo Real ---
export ANSIBLE_FORCE_COLOR = 1
export PYTHONUNBUFFERED = 1

# --- Variáveis Principais ---
PLAYBOOK  := playbooks/site.yml
PROFILE   ?= default
TAGS      ?= all
USER      ?= $(shell whoami)

# --- Destino remoto (remote/tunnel) ---
# Sem default de IP. single_host devolve o valor sem espaços nas pontas quando
# ele é um único token sem vírgula, e vazio caso contrário (espaços ou vírgulas
# viram vários hosts no inventário "$(IP)," ou quebram o ProxyCommand).
COMMA        := ,
single_host   = $(if $(filter 1,$(words $(1))),$(if $(findstring $(COMMA),$(1)),,$(strip $(1))))
TARGET_IP    := $(call single_host,$(IP))
JUMP_HOST    := $(call single_host,$(JUMP_IP))
JUMP_LOGIN   := $(call single_host,$(JUMP_USER))
REMOTE_USAGE := make remote IP=x.x.x.x [USER=usuario]
TUNNEL_USAGE := make tunnel IP=x.x.x.x JUMP_IP=y.y.y.y JUMP_USER=usuario [USER=usuario]

# Validação na leitura do Makefile: falha antes de qualquer target rodar
# (ex.: "make local remote" não provisiona o local para depois falhar).
ifneq ($(filter remote,$(MAKECMDGOALS)),)
ifeq ($(TARGET_IP),)
$(error Defina um único IP de destino: $(REMOTE_USAGE))
endif
endif
ifneq ($(filter tunnel,$(MAKECMDGOALS)),)
ifeq ($(TARGET_IP),)
$(error Defina um único IP de destino: $(TUNNEL_USAGE))
endif
ifeq ($(JUMP_HOST),)
$(error Defina um único IP do Bastion: $(TUNNEL_USAGE))
endif
ifeq ($(JUMP_LOGIN),)
$(error Defina um único usuário do Bastion: $(TUNNEL_USAGE))
endif
endif

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

.DEFAULT_GOAL := interactive

# --- Comando Base ---
ANSIBLE_CMD = ansible-playbook $(PLAYBOOK) $(ANS_FLAGS) $(ARGS)

.PHONY: help help-docs interactive menu local remote tunnel deps lint test check sandbox sandbox-shell sandbox-clean

# --- Targets ---

interactive: menu

menu:
	@bash scripts/interactive.sh

help:
	@echo ''
	@echo '${YELLOW}Workstation Ansible CLI${RESET}'
	@echo ''
	@echo '  ${GREEN}make (ou make interactive)${RESET}  Inicia o assistente interativo de provisionamento.'
	@echo '  ${GREEN}make local${RESET}          Provisiona esta máquina (localhost).'
	@echo '  ${GREEN}make remote${RESET}         Provisiona servidor remoto via SSH (exige IP=).'
	@echo '  ${GREEN}make tunnel${RESET}         Provisiona via Bastion Host (exige IP=, JUMP_IP=, JUMP_USER=).'
	@echo '  ${GREEN}make sandbox${RESET}        Provisiona em container Docker isolado (Void/Ubuntu).'
	@echo '  ${GREEN}make sandbox-shell${RESET}  Acessa o terminal interativo do container sandbox.'
	@echo '  ${GREEN}make sandbox-clean${RESET}  Para e remove o container sandbox.'
	@echo '  ${GREEN}make lint${RESET}           Executa o ansible-lint (uv run ansible-lint).'
	@echo '  ${GREEN}make test${RESET}           Executa o cenário molecule (uv run molecule test).'
	@echo '  ${GREEN}make check${RESET}          Executa lint e test.'
	@echo '  ${GREEN}make help-docs${RESET}      Exibe documentação detalhada e exemplos.'
	@echo ''
	@echo '  ${YELLOW}Opções Comuns:${RESET}'
	@echo '    TAGS=...          (zsh, docker, dotfiles, devtools, languages, node, python, rust, go)'
	@echo '    DISTRO=...        (void, ubuntu - default: void)'
	@echo '    PROFILE=...       (default, local)'
	@echo '    DRY=1             (Modo simulação)'
	@echo '    IP=...            (remote/tunnel: um único host de destino, obrigatório)'
	@echo '    USER=...          (remote/tunnel: usuário SSH - default: $$USER do shell)'
	@echo '    JUMP_IP=...       (tunnel: host do Bastion, obrigatório)'
	@echo '    JUMP_USER=...     (tunnel: usuário do Bastion, obrigatório)'

help-docs:
	@cat docs/USAGE.md
	@echo ''

deps:
	@echo "${GREEN}>> Instalando dependências do Galaxy...${RESET}"
	ansible-galaxy install -r requirements.yml 2>/dev/null || echo ">> Nenhum requirements.yml encontrado."

# --- Lint e testes (ambiente de desenvolvimento gerenciado pelo uv) ---
# O molecule é um teste adicional: não substitui o make sandbox.
# --locked: usa exatamente as versões do uv.lock e falha se ele estiver
# desatualizado, em vez de re-resolver em silêncio.
UV_RUN     := uv run --locked
REQUIRE_UV  = @command -v uv >/dev/null 2>&1 || { \
		echo "Erro: uv não encontrado. Instale-o (https://docs.astral.sh/uv/) e rode 'uv sync'." >&2; \
		exit 1; }

lint:
	$(REQUIRE_UV)
	@echo "${GREEN}>> Executando Ansible Lint...${RESET}"
	$(UV_RUN) ansible-lint

test:
	$(REQUIRE_UV)
	@if ! ls molecule/*/molecule.yml >/dev/null 2>&1; then \
		echo "Erro: nenhum cenário molecule encontrado (molecule/*/molecule.yml). Veja a issue #34." >&2; \
		exit 1; \
	fi
	@echo "${GREEN}>> Executando testes Molecule...${RESET}"
	$(UV_RUN) molecule test

# Sequencial mesmo com make -j: o test só roda se o lint passar.
check:
	@$(MAKE) --no-print-directory lint
	@$(MAKE) --no-print-directory test

local:
	@echo "${GREEN}>> Iniciando $(MSG_MODE) LOCAL [Tags: $(TAGS)]...${RESET}"
	$(ANSIBLE_CMD) -i "localhost," -c local

remote:
	@echo "${GREEN}>> Iniciando $(MSG_MODE) REMOTE em $(TARGET_IP) [Tags: $(TAGS)]...${RESET}"
	$(ANSIBLE_CMD) -i "$(TARGET_IP)," -u $(USER)

tunnel:
	@echo "${GREEN}>> Iniciando $(MSG_MODE) TUNNEL via $(JUMP_HOST) para $(TARGET_IP)...${RESET}"
	$(ANSIBLE_CMD) -i "$(TARGET_IP)," -u $(USER) \
		--ssh-common-args='-o ProxyCommand="ssh -W %h:%p -q $(JUMP_LOGIN)@$(JUMP_HOST)"'

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
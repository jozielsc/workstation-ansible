# --- Variáveis Padrão ---
PLAYBOOK := playbooks/site.yml
USER ?= $(USER)
TAGS ?= all

# --- Configuração de Cores ---
GREEN  := $(shell tput -Txterm setaf 2)
YELLOW := $(shell tput -Txterm setaf 3)
RESET  := $(shell tput -Txterm sgr0)

# --- Argumentos do Ansible ---
# Se TAGS for "all", o Ansible roda tudo. Se for específico, filtra.
ANS_TAGS := --tags "$(TAGS)"

.PHONY: help local remote tunnel lint deps

## Exibe os comandos disponíveis
help:
	@echo ''
	@echo '${YELLOW}Workstation Ansible Dev Setup - Comandos Disponíveis:${RESET}'
	@echo ''
	@echo '  ${GREEN}make local [TAGS=tag]${RESET}              Provisiona localhost. Ex: make local TAGS=dotfiles'
	@echo '  ${GREEN}make remote IP=... [TAGS=tag]${RESET}      Provisiona remoto. Ex: make remote IP=192.168.1.50'
	@echo '  ${GREEN}make tunnel IP=... JUMP_IP=...${RESET}     Provisiona via Bastion Host'
	@echo '  ${GREEN}make lint${RESET}                          Verifica sintaxe dos playbooks'
	@echo '  ${GREEN}make deps${RESET}                          Instala dependências do Ansible (Galaxy)'
	@echo ''

## 0. Instalar dependências (Galaxy)
deps:
	@echo "${GREEN}Instalando dependências do Ansible...${RESET}"
	ansible-galaxy install -r requirements.yml 2>/dev/null || echo "Nenhum requirements.yml encontrado, ignorando."

## 1. Verificação de Sintaxe (Lint)
lint:
	@echo "${GREEN}Rodando Ansible Lint...${RESET}"
	ansible-lint playbooks/*.yml

## 2. Provisionamento Local
local:
	@echo "${GREEN}Iniciando provisionamento LOCAL [Tags: $(TAGS)]...${RESET}"
	ansible-playbook $(PLAYBOOK) \
		-i "localhost," \
		-c local \
		$(ANS_TAGS) \
		-K

## 3. Provisionamento Remoto
# Uso: make remote IP=192.168.1.50 USER=joziel
remote:
ifndef IP
	$(error IP não definido. Use: make remote IP=x.x.x.x)
endif
	@echo "${GREEN}Iniciando provisionamento em $(IP) [Tags: $(TAGS)]...${RESET}"
	ansible-playbook $(PLAYBOOK) \
		-i "$(IP)," \
		-u $(USER) \
		$(ANS_TAGS) \
		-K

## 4. Provisionamento via Tunnel
# Uso: make tunnel IP=10.0.0.5 JUMP_IP=200.200.200.200 JUMP_USER=admin
tunnel:
ifndef IP
	$(error IP (destino) não definido.)
endif
ifndef JUMP_IP
	$(error JUMP_IP (bastion) não definido.)
endif
	@echo "${GREEN}Iniciando provisionamento em $(IP) via $(JUMP_IP)...${RESET}"
	ansible-playbook $(PLAYBOOK) \
		-i "$(IP)," \
		-u $(USER) \
		--ssh-common-args='-o ProxyCommand="ssh -W %h:%p -q $(JUMP_USER)@$(JUMP_IP)"' \
		$(ANS_TAGS) \
		-K

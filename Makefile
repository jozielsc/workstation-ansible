# --- Variáveis Padrão ---
PLAYBOOK := playbooks/site.yml
USER ?= $(USER)

# --- Cores para o output ---
GREEN  := $(shell tput -Txterm setaf 2)
RESET  := $(shell tput -Txterm sgr0)

.PHONY: help local remote tunnel

## Exibe os comandos disponíveis
help:
	@echo ''
	@echo 'Usage:'
	@echo '  ${GREEN}make local${RESET}                         Provisiona a própria máquina (localhost)'
	@echo '  ${GREEN}make remote IP=x.x.x.x USER=root${RESET}   Provisiona máquina remota direta'
	@echo '  ${GREEN}make tunnel IP=x.x.x.x USER=root JUMP_IP=y.y.y.y JUMP_USER=admin${RESET}'
	@echo '                                       Provisiona remota via Bastion/Jump Box'
	@echo ''

## 1. Provisionamento Local (na própria máquina)
local:
	@echo "${GREEN}Iniciando provisionamento LOCAL...${RESET}"
	ansible-playbook $(PLAYBOOK) \
		-i "localhost," \
		-c local \
		-K

## 2. Provisionamento Remoto (Acesso direto)
# Uso: make remote IP=192.168.1.50 USER=joziel
remote:
ifndef IP
	$(error IP não definido. Use: make remote IP=x.x.x.x USER=seu_usuario)
endif
	@echo "${GREEN}Iniciando provisionamento em $(IP)...${RESET}"
	ansible-playbook $(PLAYBOOK) \
		-i "$(IP)," \
		-u $(USER) \
		-K

## 3. Provisionamento Remoto via Tunnel (Jump Box)
# Uso: make tunnel IP=10.0.0.5 USER=dev JUMP_IP=200.200.200.200 JUMP_USER=admin
tunnel:
ifndef IP
	$(error IP (destino) não definido.)
endif
ifndef JUMP_IP
	$(error JUMP_IP (bastion) não definido.)
endif
	@echo "${GREEN}Iniciando provisionamento em $(IP) via Tunnel $(JUMP_IP)...${RESET}"
	ansible-playbook $(PLAYBOOK) \
		-i "$(IP)," \
		-u $(USER) \
		--ssh-common-args='-o ProxyCommand="ssh -W %h:%p -q $(JUMP_USER)@$(JUMP_IP)"' \
		-K

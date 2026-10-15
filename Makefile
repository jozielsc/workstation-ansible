# Tarefas de desenvolvimento (lint e testes). O provisionamento fica em
# scripts/workstation.sh (veja "./scripts/workstation.sh help"); este arquivo
# sai do projeto na #68, quando estas tarefas forem para o justfile.

# --- Forçar Cores e Output em Tempo Real ---
export ANSIBLE_FORCE_COLOR = 1
export PYTHONUNBUFFERED = 1

# --- Cores para Output ---
GREEN  := $(shell tput -Txterm setaf 2)
YELLOW := $(shell tput -Txterm setaf 3)
RESET  := $(shell tput -Txterm sgr0)

.DEFAULT_GOAL := help

.PHONY: help lint test check

help:
	@echo ''
	@echo '${YELLOW}Workstation Ansible - desenvolvimento${RESET}'
	@echo ''
	@echo '  ${GREEN}make lint${RESET}           Syntax-check, ansible-lint, yamllint e shellcheck (via uv).'
	@echo '  ${GREEN}make test${RESET}           Executa o cenário molecule (uv run molecule test).'
	@echo '  ${GREEN}make check${RESET}          Executa lint e test.'
	@echo ''
	@echo '  Provisionamento: ${GREEN}./scripts/workstation.sh help${RESET}'

# --- Lint e testes (ambiente de desenvolvimento gerenciado pelo uv) ---
# O molecule é um teste adicional: não substitui o sandbox
# (./scripts/workstation.sh sandbox).
# --locked: usa exatamente as versões do uv.lock e falha se ele estiver
# desatualizado, em vez de re-resolver em silêncio.
UV_RUN     := uv run --locked
REQUIRE_UV  = @command -v uv >/dev/null 2>&1 || { \
		echo "Erro: uv não encontrado. Instale-o (https://docs.astral.sh/uv/) e rode 'uv sync'." >&2; \
		exit 1; }

# As mesmas checagens do CI (.github/workflows/ci.yml), em sequência: a
# primeira que falhar interrompe as seguintes. O --syntax-check repete uma
# regra do ansible-lint, mas é rápido e dá um erro claro antes dele. O
# yamllint direto cobre também o YAML que não é de Ansible (workflows,
# configs). O shellcheck recebe todo *.sh do git ls-files, em qualquer pasta:
# a lista é a do índice do git, não a do disco. Um script novo ainda sem
# `git add` só é checado no CI, e um .sh apagado sem stage faz o shellcheck
# falhar com "does not exist". Fora de um clone git, o lint falha logo no
# início, em vez de passar sem checar os scripts.
lint:
	$(REQUIRE_UV)
	@git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { \
		echo "Erro: fora de um clone git; o shellcheck do lint usa o git ls-files." >&2; exit 1; }
	@echo "${GREEN}>> Verificando a sintaxe do playbook...${RESET}"
	$(UV_RUN) ansible-playbook playbooks/site.yml --syntax-check -i localhost,
	@echo "${GREEN}>> Executando Ansible Lint...${RESET}"
	$(UV_RUN) ansible-lint
	@echo "${GREEN}>> Executando yamllint...${RESET}"
	$(UV_RUN) yamllint --strict .
	@echo "${GREEN}>> Executando shellcheck...${RESET}"
	git ls-files -z '*.sh' | xargs -0 -r $(UV_RUN) shellcheck

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

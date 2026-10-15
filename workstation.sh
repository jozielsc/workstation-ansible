#!/usr/bin/env bash
# ==============================================================================
# Workstation Ansible - atalho na raiz do repositório
# Repassa todos os argumentos ao scripts/workstation.sh, sem lógica própria.
# Uso: ./workstation.sh [comando] [opções] [-- argumentos do ansible-playbook]
# ==============================================================================

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# WORKSTATION_PROG: o nome com que este atalho foi chamado, para que as mensagens e o wizard mostrem ./workstation.sh
# em vez do caminho de scripts/.
WORKSTATION_PROG="$0" exec "$ROOT_DIR/scripts/workstation.sh" "$@"

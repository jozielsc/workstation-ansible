# Workstation Ansible

[![Ansible](https://img.shields.io/badge/Ansible-E00-red?style=flat&logo=ansible)](https://www.ansible.com/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

> **Automate everything.** / **Automatize tudo.**

[Português](#-português) | [English](#-english)

---

## 🇧🇷 Português

Este projeto é uma solução completa de *Infrastructure as Code* (IaC) para provisionamento de ambientes de desenvolvimento. Ele transforma uma instalação limpa de Linux em uma workstation de alta produtividade em minutos.

### 🚀 Funcionalidades

- **Multiplataforma Resiliente:** Suporte nativo para **Debian/Ubuntu**, **Void Linux**, **RedHat/Fedora** e **Arch Linux**.
- **Sandbox Testing Pipeline (NOVO):** Teste todo o provisionamento em containers isolados via Docker (`Void Linux glibc` default, `Ubuntu`, `Fedora` ou `Arch`) sem alterar sua máquina local!
- **Gerenciamento Inteligente de Pacotes:** Separação de pacotes por família de SO (`Debian.yml`, `Void.yml`, `RedHat.yml`, `Archlinux.yml`) com mecanismo de instalação em lote e *fallback* tolerante a falhas por pacote.
- **Detecção de Init:** Suporte para `systemd` e `runit`.
- **Linguagens Modernas (Granular):**
  - **Python:** Gerenciado via [UV](https://github.com/astral-sh/uv) e Pipx.
  - **Node.js:** Pacotes e gerenciadores do sistema.
  - **Rust:** Instalação oficial via Rustup (com *fallback* para o pacote `cargo` do sistema).
  - **Golang:** Compilador Go.
- **Ambiente Gráfico (Opt-in Especial):** Sway WM, Waybar, Wofi, Notificações e Terminais.
- **Editores:** Neovim e ferramentas de suporte (`lldb`, utilitários de clipboard).
- **Docker Ready:** Instalação e configuração de permissões de usuário.
- **ZSH & Produtividade:** Zsh, Oh-My-Zsh, plugins (autosuggestions, syntax-highlighting) e tema Powerlevel10k.
- **Lazygit:** Instalação do binário oficial em qualquer distro (multi-arquitetura: `x86_64`, `arm64`, `armv6`).
- **Dotfiles:** Integração automática com [GNU Stow](https://www.gnu.org/software/stow/) com resolução de pré-requisitos (sem `--adopt`, preservando o conteúdo versionado do repositório).

### 📋 Pré-requisitos

Na máquina onde você executará o Ansible, é necessário apenas:
- **Git**
- **Ansible**: versão mínima, collections e ressalvas por distro (Ubuntu 22.04, Debian 11, RHEL) em [ARCHITECTURE.md](docs/ARCHITECTURE.md#collections-ansible-necessárias-no-controlador)
- **Make**
- *(Opcional)* **Docker** (para uso do Pipeline de Testes Sandbox)

#### Instalação das dependências:

- **Ubuntu/Debian:** `sudo apt update && sudo apt install -y ansible make git`
- **Void Linux:** `sudo xbps-install -S ansible make git`
- **Fedora/RHEL:** `sudo dnf install -y ansible make git`
- **Arch Linux:** `sudo pacman -S --needed ansible make git`

### 🧪 Pipeline de Testes Sandbox (Docker)

Quer testar o provisionamento antes de aplicar em sua máquina pessoal? Use o Sandbox!

1. **Rodar Sandbox em Void Linux (Padrão):**
   ```bash
   make sandbox
   ```

2. **Rodar Sandbox em Ubuntu (ou `fedora`, `arch`):**
   ```bash
   make sandbox DISTRO=ubuntu
   ```
   Em `fedora` e `arch`, a role `docker` ainda falha (#7); rode as outras tags, ex.: `TAGS=devtools,languages,zsh,editors,dotfiles`.

3. **Acessar o terminal interativo do container mantido UP:**
   ```bash
   make sandbox-shell
   ```

4. **Remover o container ao concluir:**
   ```bash
   make sandbox-clean
   ```

#### Lint e testes (desenvolvimento)

As ferramentas de desenvolvimento (`ansible`, `ansible-lint`, `yamllint`, `shellcheck`, `molecule`) são gerenciadas pelo [uv](https://docs.astral.sh/uv/) via `pyproject.toml`:

```bash
uv sync      # cria o .venv com as ferramentas
make lint    # syntax-check, ansible-lint, yamllint e shellcheck
make test    # uv run molecule test (o cenário ainda está na issue #34)
make check   # lint + test
```

O CI (GitHub Actions) roda o mesmo `make lint` em todo PR e em push na `main`. O Molecule é um teste **adicional**: não substitui o Sandbox acima.

---

### 🛠️ Instalação e Uso

1. **Clone o repositório:**
   ```bash
   git clone https://github.com/jozielsc/workstation-ansible.git
   cd workstation-ansible
   ```

2. **Escolha o modo de execução:**

   - **Modo Interativo (Recomendado / Padrão):**
     ```bash
     make
     # ou: make interactive
     ```
     *Abre o assistente TUI interativo para selecionar modo (Local, Sandbox, Remoto, Tunnel), perfil, tags e simulação (Dry-Run).*

   - **Modo Local Direct (Localhost):**
     ```bash
     make local
     ```
   - **Modo Remoto (SSH):**
     ```bash
     make remote IP=192.168.1.50 USER=root
     ```
   - **Modo Tunnel (Jump Box):**
     ```bash
     make tunnel IP=10.0.0.5 USER=dev JUMP_IP=200.200.200.200 JUMP_USER=admin
     ```

### ⚡ Execução Granular por Tags

Você pode executar partes específicas da instalação utilizando `TAGS`:

| Tag | Descrição | Exemplo de Uso |
| --- | --------- | -------------- |
| `devtools` | Ferramentas CLI base (git, tmux, fzf, stow, btop, etc.) | `make local TAGS=devtools` |
| `languages` | Instala todas as linguagens de programação | `make local TAGS=languages` |
| `python` | Instala apenas UV e Pipx | `make local TAGS=python` |
| `node` | Instala apenas Node.js/NPM | `make local TAGS=node` |
| `rust` | Instala apenas Rustup e Rust toolchain | `make local TAGS=rust` |
| `go` / `golang` | Instala apenas a linguagem Go | `make local TAGS=go` |
| `docker` | Configura Engine Docker, usuário e serviço | `make local TAGS=docker` |
| `zsh` | Configura Zsh, Oh-My-Zsh, P10k e plugins | `make local TAGS=zsh` |
| `editors` | Instala Neovim, lldb e suporte a clipboard | `make local TAGS=editors` |
| `ui` *(Opt-in)* | Instala ambiente Sway WM, Waybar e fontes (Ignorado por padrão) | `make local TAGS=ui` |
| `dotfiles` | Clona e aplica links simbólicos via GNU Stow | `make local TAGS=dotfiles` |

> ⚠️ **Nota:** A tag `ui` (interface gráfica Sway/Waybar) é estritamente **opcional (opt-in)** e ignorada por padrão para evitar modificações indesejadas em servidores ou outros ambientes. Para instalá-la, execute: `make local TAGS=ui` ou `make sandbox TAGS=ui`.

---

## 🇺🇸 English

This project is a complete Infrastructure as Code (IaC) solution for developer environment provisioning. It turns a fresh Linux install into a high-productivity workstation in minutes.

### 🚀 Features

- **Resilient Multiplatform:** Native support for **Debian/Ubuntu**, **Void Linux**, **RedHat/Fedora**, and **Arch Linux**.
- **Sandbox Testing Pipeline (NEW):** Dry-run and test provisioning in isolated Docker containers (`Void Linux glibc` default, `Ubuntu`, `Fedora` or `Arch`) without touching your local system!
- **Smart Package Management:** Distro-specific package name mapping (`Debian.yml`, `Void.yml`, `RedHat.yml`, `Archlinux.yml`) with batch installation and fault-tolerant per-package fallback.
- **Init System Detection:** Works with `systemd` and `runit`.
- **Modern Languages (Granular):**
  - **Python:** Managed via [UV](https://github.com/astral-sh/uv) and Pipx.
  - **Node.js:** System packages and package managers.
  - **Rust:** Official installation via Rustup (with a system `cargo` package fallback).
  - **Golang:** Go compiler.
- **Graphical Environment (Special Opt-in):** Sway WM, Waybar, Wofi, Notifications, and Terminals.
- **Editors:** Neovim and support tools (`lldb`, clipboard integration).
- **Docker Ready:** Installation, service configuration, and user permissions.
- **ZSH & Productivity:** Zsh, Oh-My-Zsh, plugins (autosuggestions, syntax-highlighting), and Powerlevel10k theme.
- **Lazygit:** Official binary installed on any distro (multi-arch: `x86_64`, `arm64`, `armv6`).
- **Dotfiles:** Automated [GNU Stow](https://www.gnu.org/software/stow/) integration with self-contained prerequisite checks (no `--adopt`, preserving the repository's tracked content).

### 📋 Prerequisites

On the machine running Ansible:
- **Git**
- **Ansible**: minimum version, collections and per-distro caveats (Ubuntu 22.04, Debian 11, RHEL) in [ARCHITECTURE.md](docs/ARCHITECTURE.md#collections-ansible-necessárias-no-controlador)
- **Make**
- *(Optional)* **Docker** (for Sandbox Testing Pipeline)

### 🧪 Sandbox Testing Pipeline (Docker)

Want to test provisioning safely before applying to your personal machine? Use the Sandbox!

1. **Run Sandbox in Void Linux (Default):**
   ```bash
   make sandbox
   ```

2. **Run Sandbox in Ubuntu (or `fedora`, `arch`):**
   ```bash
   make sandbox DISTRO=ubuntu
   ```
   On `fedora` and `arch`, the `docker` role still fails (#7); run the other tags, e.g. `TAGS=devtools,languages,zsh,editors,dotfiles`.

3. **Access the interactive container terminal (kept UP):**
   ```bash
   make sandbox-shell
   ```

4. **Clean up when finished:**
   ```bash
   make sandbox-clean
   ```

#### Lint and tests (development)

Development tools (`ansible`, `ansible-lint`, `yamllint`, `shellcheck`, `molecule`) are managed by [uv](https://docs.astral.sh/uv/) through `pyproject.toml`:

```bash
uv sync      # creates .venv with the tools
make lint    # syntax-check, ansible-lint, yamllint and shellcheck
make test    # uv run molecule test (the scenario is still tracked in issue #34)
make check   # lint + test
```

CI (GitHub Actions) runs the same `make lint` on every PR and on pushes to `main`. Molecule is an **additional** test: it does not replace the Sandbox above.

---

### 🛠️ Installation & Usage

1. **Clone the repository:**
   ```bash
   git clone https://github.com/jozielsc/workstation-ansible.git
   cd workstation-ansible
   ```

2. **Run provision mode:**

   - **Interactive Wizard (Recommended / Default):**
     ```bash
     make
     # or: make interactive
     ```
     *Launches an interactive TUI wizard to select target (Local, Sandbox, Remote, Tunnel), profile, tags, and Dry-Run mode.*

   - **Local Machine Direct (Localhost):**
     ```bash
     make local
     ```
   - **Remote Machine (SSH):**
     ```bash
     make remote IP=192.168.1.50 USER=root
     ```
   - **Tunnel Mode (Jump Box):**
     ```bash
     make tunnel IP=10.0.0.5 USER=dev JUMP_IP=200.200.200.200 JUMP_USER=admin
     ```

### ⚡ Granular Tag Execution

Run specific components using `TAGS`:

| Tag | Description | Example Usage |
| --- | ----------- | ------------- |
| `devtools` | Base CLI tools (git, tmux, fzf, stow, btop, etc.) | `make local TAGS=devtools` |
| `languages` | Installs all programming languages | `make local TAGS=languages` |
| `python` | Installs UV and Pipx only | `make local TAGS=python` |
| `node` | Installs Node.js/NPM only | `make local TAGS=node` |
| `rust` | Installs Rustup and Rust toolchain only | `make local TAGS=rust` |
| `go` / `golang` | Installs Go language compiler only | `make local TAGS=go` |
| `docker` | Configures Docker Engine, user groups, and service | `make local TAGS=docker` |
| `zsh` | Configures Zsh, Oh-My-Zsh, P10k, and plugins | `make local TAGS=zsh` |
| `editors` | Installs Neovim, lldb, and clipboard tools | `make local TAGS=editors` |
| `ui` *(Opt-in)* | Installs Sway WM, Waybar, and fonts (Skipped by default) | `make local TAGS=ui` |
| `dotfiles` | Clones and links dotfiles via GNU Stow | `make local TAGS=dotfiles` |

> ⚠️ **Note:** The `ui` tag (graphical desktop environment Sway/Waybar) is strictly **opt-in** and skipped by default to prevent unintended changes on server or other desktop environments. To install it, run: `make local TAGS=ui` or `make sandbox TAGS=ui`.

---

## 📂 Directory Structure / Estrutura do Projeto

```plaintext
workstation-ansible/
├── Makefile              # Task runner CLI helper (includes sandbox, lint and test targets)
├── pyproject.toml        # uv dev environment (ansible, linters, molecule) + uv.lock
├── .github/workflows/    # CI: make lint on PRs and pushes to main
├── README.md             # Documentation (Bilingual)
├── profiles/             # Configuration profiles (default.yml, local.sample.yml)
├── playbooks/
│   ├── site.yml          # Entry point playbook
│   └── roles/
│       ├── devtools/     # Base CLI tools & resilient package installer
│       ├── languages/    # Modular language tasks (python, node, rust, go)
│       │   └── tasks/    # python.yml, node.yml, rust.yml, go.yml
│       ├── docker/       # Docker Engine + init service setup
│       ├── zsh/          # Shell setup (Zsh, OMZ, P10k, plugins)
│       ├── editors/      # Editors (Neovim, lldb, clipboard)
│       ├── ui/           # Graphical Environment (Sway, Waybar, Fonts - Opt-in)
│       └── dotfiles/     # GNU Stow symlink integration
└── tests/
    └── sandbox/          # Sandbox test pipeline Dockerfiles (void, ubuntu, fedora, arch)
```

---

## 📄 License / Licença

MIT License. See [LICENSE](LICENSE) for details.
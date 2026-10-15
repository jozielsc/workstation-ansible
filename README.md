# Workstation Ansible

[![Ansible](https://img.shields.io/badge/Ansible-E00-red?style=flat&logo=ansible)](https://www.ansible.com/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

> **Automate everything.** / **Automatize tudo.**

[Português](#-português) | [English](#-english)

---

## 🇧🇷 Português

Este projeto é uma solução completa de *Infrastructure as Code* (IaC) para provisionamento de ambientes de desenvolvimento. Ele transforma uma instalação limpa de Linux em uma workstation de alta produtividade em minutos.

### 🚀 Funcionalidades

- **Multiplataforma Resiliente:** Suporte nativo para **Debian/Ubuntu**, **Void Linux**, **RedHat/Fedora** e **Arch Linux**. Em outra distro, o provisionamento para logo no início com uma mensagem clara (veja o [manual](docs/USAGE.md#requisitos) para forçar).
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
- *(Opcional)* **Docker** (para uso do Pipeline de Testes Sandbox)

#### Instalação das dependências:

- **Ubuntu/Debian:** `sudo apt update && sudo apt install -y ansible git`
- **Void Linux:** `sudo xbps-install -S ansible git`
- **Fedora/RHEL:** `sudo dnf install -y ansible git`
- **Arch Linux:** `sudo pacman -S --needed ansible git`

### 🧪 Pipeline de Testes Sandbox (Docker)

Quer testar o provisionamento antes de aplicar em sua máquina pessoal? Use o Sandbox!

1. **Rodar Sandbox em Void Linux (Padrão):**
   ```bash
   ./scripts/workstation.sh sandbox
   ```

2. **Rodar Sandbox em Ubuntu (ou `fedora`, `arch`):**
   ```bash
   ./scripts/workstation.sh sandbox --distro ubuntu
   ```

3. **Acessar o terminal interativo do container mantido UP:**
   ```bash
   ./scripts/workstation.sh sandbox-shell
   ```

4. **Remover o container ao concluir:**
   ```bash
   ./scripts/workstation.sh sandbox-clean
   ```

#### Lint e testes (desenvolvimento)

As ferramentas de desenvolvimento (`ansible`, `ansible-lint`, `yamllint`, `shellcheck`, `molecule`) são gerenciadas pelo [uv](https://docs.astral.sh/uv/) via `pyproject.toml`, inclusive o [just](https://github.com/casey/just), que roda as receitas do `justfile`:

```bash
uv sync                        # cria o .venv com as ferramentas
uv run just                    # lista as receitas
uv run just lint               # syntax-check, ansible-lint, yamllint e shellcheck
uv run just test               # uv run molecule test (o cenário ainda está na issue #34)
uv run just check              # lint + test
uv run just sandbox ubuntu rust  # ./scripts/workstation.sh sandbox --distro ubuntu --tags rust
```

O CI (GitHub Actions) roda o mesmo `just lint` em todo PR e em push na `main`. O Molecule é um teste **adicional**: não substitui o Sandbox acima.

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
     ./scripts/workstation.sh
     ```
     *Abre o assistente TUI interativo para selecionar modo (Local, Sandbox, Remoto, Tunnel), perfil, tags e simulação (Dry-Run).*

   - **Modo Local Direct (Localhost):**
     ```bash
     ./scripts/workstation.sh local
     ```
   - **Modo Remoto (SSH):**
     ```bash
     ./scripts/workstation.sh remote --ip 192.168.1.50 --user root
     ```
   - **Modo Tunnel (Jump Box):**
     ```bash
     ./scripts/workstation.sh tunnel --ip 10.0.0.5 --user dev --jump-ip 200.200.200.200 --jump-user admin
     ```

   Na raiz do repositório, `./workstation.sh` é um atalho para `./scripts/workstation.sh`, com os mesmos comandos e opções (por exemplo, `./workstation.sh local`).

### ⚡ Execução Granular por Tags

Você pode executar partes específicas da instalação utilizando `--tags`:

| Tag | Descrição | Exemplo de Uso |
| --- | --------- | -------------- |
| `devtools` | Ferramentas CLI base (git, tmux, fzf, stow, btop, etc.) | `./scripts/workstation.sh local --tags devtools` |
| `languages` | Instala todas as linguagens de programação | `./scripts/workstation.sh local --tags languages` |
| `python` | Instala apenas UV e Pipx | `./scripts/workstation.sh local --tags python` |
| `node` | Instala apenas Node.js/NPM | `./scripts/workstation.sh local --tags node` |
| `rust` | Instala apenas Rustup e Rust toolchain | `./scripts/workstation.sh local --tags rust` |
| `go` / `golang` | Instala apenas a linguagem Go | `./scripts/workstation.sh local --tags go` |
| `docker` | Configura Engine Docker, usuário e serviço | `./scripts/workstation.sh local --tags docker` |
| `zsh` | Configura Zsh, Oh-My-Zsh, P10k e plugins | `./scripts/workstation.sh local --tags zsh` |
| `editors` | Instala Neovim, lldb e suporte a clipboard | `./scripts/workstation.sh local --tags editors` |
| `ui` *(Opt-in)* | Instala ambiente Sway WM, Waybar e fontes (Ignorado por padrão) | `./scripts/workstation.sh local --tags ui` |
| `dotfiles` | Clona e aplica links simbólicos via GNU Stow | `./scripts/workstation.sh local --tags dotfiles` |

> ⚠️ **Nota:** A tag `ui` (interface gráfica Sway/Waybar) é estritamente **opcional (opt-in)** e ignorada por padrão para evitar modificações indesejadas em servidores ou outros ambientes. Para instalá-la, execute: `./scripts/workstation.sh local --tags ui` ou `./scripts/workstation.sh sandbox --tags ui`.

---

## 🇺🇸 English

This project is a complete Infrastructure as Code (IaC) solution for developer environment provisioning. It turns a fresh Linux install into a high-productivity workstation in minutes.

### 🚀 Features

- **Resilient Multiplatform:** Native support for **Debian/Ubuntu**, **Void Linux**, **RedHat/Fedora**, and **Arch Linux**. On any other distro, provisioning stops right at the start with a clear message (see the [manual](docs/USAGE.md#requisitos) to force it).
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
- *(Optional)* **Docker** (for Sandbox Testing Pipeline)

### 🧪 Sandbox Testing Pipeline (Docker)

Want to test provisioning safely before applying to your personal machine? Use the Sandbox!

1. **Run Sandbox in Void Linux (Default):**
   ```bash
   ./scripts/workstation.sh sandbox
   ```

2. **Run Sandbox in Ubuntu (or `fedora`, `arch`):**
   ```bash
   ./scripts/workstation.sh sandbox --distro ubuntu
   ```

3. **Access the interactive container terminal (kept UP):**
   ```bash
   ./scripts/workstation.sh sandbox-shell
   ```

4. **Clean up when finished:**
   ```bash
   ./scripts/workstation.sh sandbox-clean
   ```

#### Lint and tests (development)

Development tools (`ansible`, `ansible-lint`, `yamllint`, `shellcheck`, `molecule`) are managed by [uv](https://docs.astral.sh/uv/) through `pyproject.toml`, including [just](https://github.com/casey/just), which runs the `justfile` recipes:

```bash
uv sync                        # creates .venv with the tools
uv run just                    # lists the recipes
uv run just lint               # syntax-check, ansible-lint, yamllint and shellcheck
uv run just test               # uv run molecule test (the scenario is still tracked in issue #34)
uv run just check              # lint + test
uv run just sandbox ubuntu rust  # ./scripts/workstation.sh sandbox --distro ubuntu --tags rust
```

CI (GitHub Actions) runs the same `just lint` on every PR and on pushes to `main`. Molecule is an **additional** test: it does not replace the Sandbox above.

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
     ./scripts/workstation.sh
     ```
     *Launches an interactive TUI wizard to select target (Local, Sandbox, Remote, Tunnel), profile, tags, and Dry-Run mode.*

   - **Local Machine Direct (Localhost):**
     ```bash
     ./scripts/workstation.sh local
     ```
   - **Remote Machine (SSH):**
     ```bash
     ./scripts/workstation.sh remote --ip 192.168.1.50 --user root
     ```
   - **Tunnel Mode (Jump Box):**
     ```bash
     ./scripts/workstation.sh tunnel --ip 10.0.0.5 --user dev --jump-ip 200.200.200.200 --jump-user admin
     ```

   At the repository root, `./workstation.sh` is a shortcut for `./scripts/workstation.sh`, with the same commands and options (for example, `./workstation.sh local`).

### ⚡ Granular Tag Execution

Run specific components using `--tags`:

| Tag | Description | Example Usage |
| --- | ----------- | ------------- |
| `devtools` | Base CLI tools (git, tmux, fzf, stow, btop, etc.) | `./scripts/workstation.sh local --tags devtools` |
| `languages` | Installs all programming languages | `./scripts/workstation.sh local --tags languages` |
| `python` | Installs UV and Pipx only | `./scripts/workstation.sh local --tags python` |
| `node` | Installs Node.js/NPM only | `./scripts/workstation.sh local --tags node` |
| `rust` | Installs Rustup and Rust toolchain only | `./scripts/workstation.sh local --tags rust` |
| `go` / `golang` | Installs Go language compiler only | `./scripts/workstation.sh local --tags go` |
| `docker` | Configures Docker Engine, user groups, and service | `./scripts/workstation.sh local --tags docker` |
| `zsh` | Configures Zsh, Oh-My-Zsh, P10k, and plugins | `./scripts/workstation.sh local --tags zsh` |
| `editors` | Installs Neovim, lldb, and clipboard tools | `./scripts/workstation.sh local --tags editors` |
| `ui` *(Opt-in)* | Installs Sway WM, Waybar, and fonts (Skipped by default) | `./scripts/workstation.sh local --tags ui` |
| `dotfiles` | Clones and links dotfiles via GNU Stow | `./scripts/workstation.sh local --tags dotfiles` |

> ⚠️ **Note:** The `ui` tag (graphical desktop environment Sway/Waybar) is strictly **opt-in** and skipped by default to prevent unintended changes on server or other desktop environments. To install it, run: `./scripts/workstation.sh local --tags ui` or `./scripts/workstation.sh sandbox --tags ui`.

---

## 📂 Directory Structure / Estrutura do Projeto

```plaintext
workstation-ansible/
├── justfile              # Development tasks: lint, test, check, sandbox (uv run just)
├── workstation.sh        # Shortcut at the root: forwards to scripts/workstation.sh
├── scripts/
│   ├── workstation.sh    # Provisioning entry point (local, remote, tunnel, sandbox, wizard)
│   ├── interactive.sh    # Interactive TUI wizard
│   └── lib/quote.sh      # Shell quoting shared by both scripts
├── pyproject.toml        # uv dev environment (ansible, linters, molecule) + uv.lock
├── .github/workflows/    # CI: just lint on PRs and pushes to main
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
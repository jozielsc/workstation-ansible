# Workstation Ansible

[![Ansible](https://img.shields.io/badge/Ansible-E00-red?style=flat&logo=ansible)](https://www.ansible.com/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

> **Automate everything.**

Este projeto é uma solução completa de *Infrastructure as Code* (IaC) para provisionamento de ambientes de desenvolvimento. Ele transforma uma instalação limpa de Linux (Void, Ubuntu, Debian, etc.) em uma workstation de alta produtividade em minutos.

## 🚀 Funcionalidades

- **Multiplataforma:** Suporte nativo para **Void Linux** e **Debian/Ubuntu** (extensível para outras distros).
- **Gerenciamento Inteligente:** Detecta automaticamente o gerenciador de pacotes (`xbps`, `apt`) e sistema de init (`runit`, `systemd`).
- **Linguagens Modernas:**
  - **Node.js:** Gerenciado via [Volta](https://volta.sh/) (rápido e isolado).
  - **Python:** Gerenciado via [UV](https://github.com/astral-sh/uv) e Pipx.
  - **Rust:** Instalação via Rustup.
- **Ambiente Gráfico (Sway):** Instalação completa do Sway WM, Waybar, Wofi e terminais (Alacritty/Foot).
- **Editores:** Configuração pronta para **Neovim** e outros editores.
- **Docker Ready:** Instalação e configuração de permissões de usuário.
- **ZSH & Produtividade:** Configuração automática do Zsh, Oh-My-Zsh, plugins e tema Powerlevel10k.
- **Dotfiles:** Integração automática com [GNU Stow](https://www.gnu.org/software/stow/) para gerenciar seus arquivos de configuração.

---

## 📋 Pré-requisitos

Na máquina de origem (onde você roda o comando), você precisa apenas de:

- **Git**
- **Ansible**
- **Make**

### Instalação rápida das dependências:

**Ubuntu/Debian:**
```bash
sudo apt update && sudo apt install -y ansible make git
```
**Void Linux:**
```bash
sudo xbps-install -S ansible make git
```
**macOS:**
```bash
brew install ansible make git
```

## 🛠️ Instalação e Uso

1. Clone o repositório
```bash
git clone https://github.com/jozielsc/workstation-ansible.git
cd workstation-ansible
```

2. Instale dependências do Ansible (Opcional)
Se o projeto utilizar roles externas do Galaxy:
```bash
make deps
```

3. Escolha seu modo de provisionamento
O projeto utiliza um Makefile robusto para simplificar os comandos complexos do Ansible.

### 🏠 Modo Local (Minha Máquina)
Configura o computador atual (localhost). Solicitará a senha de sudo para instalações de sistema.
```bash
make local
```

### 🌐 Modo Remoto (Servidor/VPS)
Configura uma máquina remota acessível via SSH. Substitua o IP e o USER pelos dados reais.
```bash
make remote IP=192.168.1.50 USER=root
```

### 🚇 Modo Tunnel (Via Bastion/Jump Box)
Ideal para redes corporativas ou privadas onde o alvo (ex: 10.0.0.5) só é acessível através de um servidor de borda (Jump Box).
```bash
make tunnel IP=10.0.0.5 USER=dev JUMP_IP=200.200.200.200 JUMP_USER=admin
```

## ⚡ Usando Tags (Agilidade)

Não quer rodar o playbook inteiro? Use TAGS para executar apenas partes específicas.

| Tag | Descrição | Exemplo de Uso |
| --- | --------- | -------------- |
| `dotfiles` | Atualiza apenas os links simbólicos (Stow) | `make local TAGS=dotfiles` |
| `zsh` | Reconfigura shell e plugins | `make local TAGS=zsh` |
| `node` | Instala/Atualiza Node.js e Volta | `make local TAGS=node` |
| `python` | Instala UV, Pipx e pacotes Python | `make local TAGS=python` |
| `docker` | Configura Docker e serviços | `make local TAGS=docker` |
| `editors` | Instala Neovim e editores | `make local TAGS=editors` |
| `ui` | Instala Sway, Waybar, Fontes | `make local TAGS=ui` |

## ⚙️ Personalização (Profiles)

Você pode personalizar as variáveis de instalação (como pacotes extras ou editores) sem alterar o código do repositório.

1. Copie o arquivo de exemplo:
   ```bash
   cp profiles/local.sample.yml profiles/local.yml
   ```
2. Edite `profiles/local.yml` conforme sua necessidade:
   ```yaml
   editors_packages:
     - neovim
     - code # VSCode

   ui_features:
     fonts: true # Instala Nerd Fonts
   ```
   > O arquivo `profiles/local.yml` é ignorado pelo Git, garantindo que suas configurações pessoais não sejam enviadas ao repositório.

## 📂 Estrutura do Projeto

```plaintext
workstation-ansible/
├── Makefile              # Facilitador de comandos CLI (Task Runner)
├── README.md             # Documentação
├── profiles/             # Perfis de configuração (default, local)
├── playbooks/
│   ├── site.yml          # Playbook principal (Entry point)
│   └── roles/
│       ├── devtools/     # Ferramentas básicas (git, curl, tmux)
│       ├── languages/    # Setup de Node, Python, Rust
│       ├── docker/       # Engine Docker + Compose
│       ├── zsh/          # Shell setup (OMZ, P10k)
│       ├── editors/      # Neovim, VSCode, etc.
│       ├── ui/           # Sway, Waybar, Fonts (Ambiente Gráfico)
│       └── dotfiles/     # Linkagem de configurações (Stow)
```

## ⚙️ Adicionar Novas Distros

Para adicionar suporte a um novo sistema (ex: Fedora):

1. Descubra a "Família do OS":
   ```bash
   ansible localhost -m setup -a "filter=ansible_os_family"
   ```
2. Crie um arquivo com esse nome em `playbooks/roles/<role>/vars/`.
   - Exemplo: `playbooks/roles/devtools/vars/RedHat.yml`
3. Liste os pacotes equivalentes para aquela distro dentro do arquivo.

## 🤝 Contribuição

Sinta-se à vontade para abrir Issues ou Pull Requests para adicionar suporte a novas distros, ferramentas ou melhorias no fluxo de trabalho.

## 📄 Licença
Este projeto está sob a licença MIT. Veja o arquivo LICENSE para mais detalhes.
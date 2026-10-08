# Workstation Ansible - Manual de Uso

Este projeto visa automatizar a configuração do seu ambiente de desenvolvimento. Abaixo estão os detalhes sobre como operar o sistema, personalizar perfis, testar em ambiente sandbox e solucionar problemas.

## Requisitos

Na máquina que executa o Ansible: `git`, `make` e o Ansible. A versão mínima, as collections necessárias e as ressalvas por distro (Ubuntu 22.04, Debian 11, RHEL) estão em [ARCHITECTURE.md](ARCHITECTURE.md#collections-ansible-necessárias-no-controlador).

## Comandos Principais (Makefile)

O arquivo `Makefile` é a interface principal:

*   `make` (ou `make interactive` / `make menu`): Inicia o assistente TUI interativo para configurar e provisionar o ambiente passo a passo.
*   `make local`: Configura a máquina atual (localhost).
*   `make remote IP=<IP> USER=<USER>`: Configura uma máquina remota via SSH.
*   `make tunnel IP=<IP> JUMP_IP=<JUMP_IP>`: Configura uma máquina através de um Bastion Host.
*   `make sandbox [DISTRO=void|ubuntu]`: Cria um container Docker isolado, executa o Ansible e o mantém ativo para testes.
*   `make sandbox-shell`: Abre o terminal interativo (`bash`) no container sandbox atual.
*   `make sandbox-clean`: Para e remove o container sandbox.
*   `make deps`: Deveria instalar as dependências do Galaxy, mas hoje não faz nada, porque não existe `requirements.yml` (#20). Veja como obter as collections em [ARCHITECTURE.md](ARCHITECTURE.md#collections-ansible-necessárias-no-controlador).
*   `make lint`: Executa o `ansible-lint` no repositório (`uv run ansible-lint`).
*   `make test`: Executa o cenário Molecule (`uv run molecule test`). Enquanto o cenário não existir (#34), para com uma mensagem.
*   `make check`: Executa `lint` e depois `test`.

`lint`, `test` e `check` usam o ambiente de desenvolvimento do [uv](https://docs.astral.sh/uv/) (`pyproject.toml`). Rode `uv sync` uma vez antes. O Molecule é um teste adicional: não substitui o `make sandbox`.

### Variáveis de Controle

Você pode passar variáveis extras para qualquer comando `make`:

*   `TAGS`: Lista de tags separadas por vírgula para executar apenas partes específicas.
    *   Exemplo: `make local TAGS=zsh,dotfiles` ou `make sandbox DISTRO=ubuntu TAGS=node`
*   `PROFILE`: Define qual perfil de variáveis carregar (padrão: `default`).
    *   Exemplo: `make local PROFILE=local`
*   `DISTRO`: Escolhe a distribuição para o sandbox Docker (padrão: `void`, suporte: `void`, `ubuntu`).
    *   Exemplo: `make sandbox DISTRO=ubuntu`
*   `DRY`: Se definido (`DRY=1`), executa em modo de simulação (Check Mode), mostrando o que seria alterado sem aplicar nada.

---

## Pipeline de Testes Sandbox (Docker)

Para testar o provisionamento sem afetar sua máquina pessoal ou servidor, o projeto inclui um ambiente Sandbox isolado via Docker:

1. **Executar o Sandbox (Default: Void Linux):**
   ```bash
   make sandbox
   ```

2. **Executar em outra distro (ex: Ubuntu):**
   ```bash
   make sandbox DISTRO=ubuntu
   ```

3. **Testar uma tag específica no Sandbox:**
   ```bash
   make sandbox DISTRO=void TAGS=python
   ```

4. **Acessar o terminal do container para inspecionar os pacotes instalados:**
   ```bash
   make sandbox-shell DISTRO=void
   ```

5. **Limpar o container ao finalizar:**
   ```bash
   make sandbox-clean DISTRO=void
   ```

---

## Perfis (Profiles) e Resolução de Pacotes

Os perfis definem pacotes extras e ativam/desativam recursos.

*   **Padrão (`profiles/default.yml`)**: Define a habilitação de recursos base e linguagens.
*   **Mapeamento por Distribuição (`playbooks/roles/*/vars/`)**: Pacotes do sistema são gerenciados automaticamente pelo SO detectado (`Debian.yml`, `Void.yml`, `RedHat.yml`, `Archlinux.yml`).
*   **Personalização Local (`profiles/local.yml`)**: Crie copiando `cp profiles/local.sample.yml profiles/local.yml`. Edite as variáveis `devtools_extra_packages`, `editors_extra_packages`, `ui_extra_packages` para adicionar ferramentas pessoais.

---

## Tags Disponíveis

Use tags para agilizar a execução quando quiser alterar apenas um componente:

*   `devtools`: Pacotes base CLI (git, curl, tmux, fzf, stow, btop, etc.).
*   `languages`: Instala todas as linguagens de programação ativas.
    *   `python`: Instala apenas UV e Pipx.
    *   `node`: Instala apenas Node.js/NPM.
    *   `rust`: Instala apenas Rustup e Cargo.
    *   `go` / `golang`: Instala apenas Golang.
*   `docker`: Instalação do Docker e Docker Compose.
*   `zsh`: Configuração do Shell Zsh, Oh-My-Zsh e Powerlevel10k.
*   `editors`: Neovim, lldb e ferramentas de clipboard.
*   `ui` *(Opt-in especial)*: Interface gráfica Sway, Waybar e fontes. *(Ignorado por padrão)*.
*   `dotfiles`: Gerenciamento de arquivos de configuração via GNU Stow.

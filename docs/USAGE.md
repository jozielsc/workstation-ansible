# Workstation Ansible - Manual de Uso

Este projeto visa automatizar a configuração do seu ambiente de desenvolvimento. Abaixo estão os detalhes sobre como operar o sistema, personalizar perfis, testar em ambiente sandbox e solucionar problemas.

## Comandos Principais (Makefile)

O arquivo `Makefile` é a interface principal:

*   `make local`: Configura a máquina atual (localhost).
*   `make remote IP=<IP> USER=<USER>`: Configura uma máquina remota via SSH.
*   `make tunnel IP=<IP> JUMP_IP=<JUMP_IP>`: Configura uma máquina através de um Bastion Host.
*   `make sandbox [DISTRO=void|ubuntu]`: Cria um container Docker isolado, executa o Ansible e o mantém ativo para testes.
*   `make sandbox-shell`: Abre o terminal interativo (`bash`) no container sandbox atual.
*   `make sandbox-clean`: Para e remove o container sandbox.
*   `make deps`: Instala dependências do Ansible (roles/collections do Galaxy).
*   `make lint`: Executa verificação de sintaxe nos playbooks.

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

# Workstation Ansible - Manual de Uso

Este projeto visa automatizar a configuração do seu ambiente de desenvolvimento. Abaixo estão os detalhes sobre como operar o sistema, personalizar perfis, testar em ambiente sandbox e solucionar problemas.

## Requisitos

Na máquina que executa o Ansible: `git`, `bash` e o Ansible. A versão mínima, as collections necessárias e as ressalvas por distro (Ubuntu 22.04, Debian 11, RHEL) estão em [ARCHITECTURE.md](ARCHITECTURE.md#collections-ansible-necessárias-no-controlador).

Na máquina provisionada: uma distro das famílias Debian/Ubuntu, Void, RedHat/Fedora ou Arch. Em outra distro (Alpine, openSUSE…), o provisionamento para logo no início, antes de pedir sudo, com uma mensagem que mostra a distro detectada. O host precisa ter `python3`. A checagem é por família: derivados como Linux Mint ou Pop!_OS passam, mas a instalação do Docker ainda falha neles (#22). Para forçar mesmo assim, sabendo que só uma parte será instalada, passe `-- -e allow_unsupported_distro=true` (por exemplo, `./scripts/workstation.sh local -- -e allow_unsupported_distro=true`) ou defina `allow_unsupported_distro: true` no `profiles/local.yml`.

## Comandos Principais (`scripts/workstation.sh`)

O script `scripts/workstation.sh` é a interface principal. Rode-o da raiz do repositório (`./scripts/workstation.sh …`) ou de qualquer pasta, pelo caminho; ele funciona a partir do bash ou do zsh. Caminhos relativos depois de `--` valem a partir da pasta de onde você chamou o script. `./scripts/workstation.sh help` lista os comandos e as opções. Na raiz, `./workstation.sh` é um atalho para ele, com os mesmos comandos e opções (por exemplo, `./workstation.sh local`); as mensagens e o wizard passam a mostrar o atalho.

*   `./scripts/workstation.sh` (sem comando): Inicia o assistente TUI interativo para configurar e provisionar o ambiente passo a passo. Usa o `dialog`; sem ele, o `whiptail`; sem nenhum dos dois, um modo texto (`TUI_ENGINE=dialog|whiptail|cli` força um motor: se ele não existir ou falhar, o assistente sai com erro em vez de trocar de motor). Sem `TUI_ENGINE`, se a interface falhar (por exemplo, sem terminal), o assistente avisa e continua no próximo motor, no mesmo passo. No `dialog`, os botões são OK, Back e Cancel; nas perguntas de sim/não, Yes, Back, No e Cancel. No `whiptail`, que só tem dois botões, o segundo botão (**Voltar/Cancelar**) abre um menu para voltar à tela anterior, cancelar o assistente ou continuar nesta tela (ela reabre com os valores de quando foi aberta). No modo texto, nos menus, digite o número da opção (Enter mantém a opção atual). No passo de componentes, os números separados por espaço **invertem** a marcação dos itens indicados (vários já vêm marcados) e a lista aparece de novo com as marcas atualizadas; Enter sem nada confirma a seleção mostrada. Digite `b` para voltar e `c` para cancelar; Ctrl-D também cancela quando nada foi digitado (depois de um valor, ele vale como Enter). Sem terminal, as respostas podem vir pelo stdin; se acabarem antes do fim, o assistente sai com erro. Nas perguntas de sim/não (simulação e confirmação), só uma resposta que começa com `y` confirma; qualquer outra, inclusive Enter vazio, é "não".
*   `./scripts/workstation.sh local`: Configura a máquina atual (localhost).
*   `./scripts/workstation.sh remote --ip <IP> [--user <USER>]`: Configura uma máquina remota via SSH. O `--ip` é obrigatório e deve ser um único host. Hosts e usuários só aceitam letras, números e `.`, `_`, `-`, sem começar com `-`; o `--user` aceita também `@` (por exemplo, `jdoe@corp.example`). IPv6 e outra porta SSH não são aceitos: para eles, crie um alias (`Host`, com `HostName` e `Port`) no `~/.ssh/config` e passe o nome do alias. Sem `--user`, o usuário SSH é o usuário atual (`whoami`).
*   `./scripts/workstation.sh tunnel --ip <IP> --jump-ip <JUMP_IP> --jump-user <JUMP_USER> [--user <USER>]`: Configura uma máquina através de um Bastion Host. `--ip`, `--jump-ip` e `--jump-user` são obrigatórios, com as mesmas regras de caracteres do `remote`.
*   `./scripts/workstation.sh sandbox [--distro void|ubuntu|fedora|arch]`: Cria um container Docker isolado, executa o Ansible e o mantém ativo para testes.
*   `./scripts/workstation.sh sandbox-shell [--distro …]`: Abre o terminal interativo (`bash`) no container sandbox da distro. Como no `sandbox` e no `sandbox-clean`, a distro precisa ter um Dockerfile em `tests/sandbox/`.
*   `./scripts/workstation.sh sandbox-clean [--distro …]`: Para e remove o container sandbox da distro.
*   `./scripts/workstation.sh help` / `help-docs`: Mostra os comandos e as opções / este manual.

Não há comando para instalar as collections do Ansible (#20). Veja como obtê-las em [ARCHITECTURE.md](ARCHITECTURE.md#collections-ansible-necessárias-no-controlador).

As tarefas de desenvolvimento ficam no `justfile` e rodam com o [just](https://github.com/casey/just), que vem do ambiente de desenvolvimento do uv. `uv run just` lista as receitas:

*   `uv run just lint`: Executa, em sequência, o `--syntax-check` do playbook, o `ansible-lint`, o `yamllint` e o `shellcheck` dos scripts. São as mesmas checagens do CI que roda nos PRs.
*   `uv run just test`: Executa o cenário Molecule (`uv run molecule test`). Enquanto o cenário não existir (#34), para com uma mensagem.
*   `uv run just check`: Executa `lint` e, se ele passar, `test`.
*   `uv run just sandbox [distro] [tags] [argumentos]`: Atalho para `./scripts/workstation.sh sandbox --distro <distro> --tags <tags>` (padrão: `void` e `all`); os argumentos extras vão para o `ansible-playbook`. Para passar argumentos extras, informe antes a distro e as tags, mesmo que sejam as padrão: `uv run just sandbox ubuntu rust -vv` ou `uv run just sandbox void all -vv`. Em `uv run just sandbox ubuntu -vv`, o `-vv` seria lido como as tags, e a receita sai com erro. Como no script, caminhos relativos nos argumentos extras (`-e @vars.yml`) valem a partir da pasta de onde você chamou.

As receitas usam o ambiente de desenvolvimento do [uv](https://docs.astral.sh/uv/) (`pyproject.toml`). Rode `uv sync` uma vez antes. Com o `.venv` ativado, basta `just <receita>`. Quem só provisiona não precisa do uv nem do just. O Molecule é um teste adicional: não substitui o sandbox.

### Opções

As opções aceitam `--opção valor` e `--opção=valor`; um valor que começa com `-` só vale na segunda forma. Uma opção com valor vazio ou que não se aplica ao comando (por exemplo, `--ip` com `local`) é recusada com erro.

*   `--tags`: Lista de tags separadas por vírgula para executar apenas partes específicas (`local`, `remote`, `tunnel`, `sandbox`).
    *   Exemplo: `./scripts/workstation.sh local --tags zsh,dotfiles` ou `./scripts/workstation.sh sandbox --distro ubuntu --tags node`
*   `--profile`: Define qual perfil de variáveis carregar (padrão: `default`). Precisa existir um arquivo `profiles/<nome>.yml`.
    *   Exemplo: `./scripts/workstation.sh local --profile local`
*   `--distro`: Escolhe a distribuição para o sandbox Docker (padrão: `void`, suporte: `void`, `ubuntu`, `fedora`, `arch`).
    *   Exemplo: `./scripts/workstation.sh sandbox --distro ubuntu`
*   `--dry-run`: Executa em modo de simulação (Check Mode), mostrando o que seria alterado sem aplicar nada. O `sandbox` ainda o ignora e avisa que a execução é real (#12).
*   `--print`: Mostra os comandos (`ansible-playbook`, `docker`) sem executá-los. O `ansible-playbook` aparece como `env ANSIBLE_CONFIG=… ansible-playbook …`, então pode ser colado e executado em qualquer pasta.
*   `-- <argumentos>`: Tudo depois de `--` vai para o `ansible-playbook`. Exemplo: `./scripts/workstation.sh local -- -vvv`.

---

## Pipeline de Testes Sandbox (Docker)

Para testar o provisionamento sem afetar sua máquina pessoal ou servidor, o projeto inclui um ambiente Sandbox isolado via Docker:

1. **Executar o Sandbox (Default: Void Linux):**
   ```bash
   ./scripts/workstation.sh sandbox
   ```

2. **Executar em outra distro (`ubuntu`, `fedora` ou `arch`; ex: Ubuntu):**
   ```bash
   ./scripts/workstation.sh sandbox --distro ubuntu
   ```

3. **Testar uma tag específica no Sandbox:**
   ```bash
   ./scripts/workstation.sh sandbox --distro void --tags python
   ```

4. **Acessar o terminal do container para inspecionar os pacotes instalados:**
   ```bash
   ./scripts/workstation.sh sandbox-shell --distro void
   ```

5. **Limpar o container ao finalizar:**
   ```bash
   ./scripts/workstation.sh sandbox-clean --distro void
   ```

---

## Perfis (Profiles) e Resolução de Pacotes

Os perfis definem pacotes extras e ativam/desativam recursos.

*   **Padrão (`profiles/default.yml`)**: Define a habilitação de recursos base e linguagens.
*   **Mapeamento por Distribuição (`playbooks/roles/*/vars/`)**: Pacotes do sistema são gerenciados automaticamente pelo SO detectado (`Debian.yml`, `Void.yml`, `RedHat.yml`, `Archlinux.yml`).
*   **Personalização Local (`profiles/local.yml`)**: Crie copiando `cp profiles/local.sample.yml profiles/local.yml`. Edite as variáveis `devtools_extra_packages`, `editors_extra_packages`, `ui_extra_packages` para adicionar ferramentas pessoais. O arquivo é opcional, mas, se existir, precisa ser YAML válido: um `local.yml` quebrado faz qualquer execução falhar logo no início.

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

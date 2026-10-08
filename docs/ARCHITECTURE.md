# Workstation Ansible - Arquitetura

Documento de referência técnica para quem vai modificar o projeto. Para uso do dia a dia, veja [USAGE.md](USAGE.md). Problemas conhecidos e dívida técnica estão em [TECH_DEBT.md](TECH_DEBT.md).

## Visão geral do fluxo

```
make  (sem target)
  └─ scripts/interactive.sh      wizard TUI (whiptail > dialog > CLI puro)
       └─ make <modo> PROFILE=… TAGS=… [DRY=1] [DISTRO=… | IP=… USER=… JUMP_IP=… JUMP_USER=…]

make local | remote | tunnel
  └─ ansible-playbook playbooks/site.yml -K --tags "$TAGS" -e profile=$PROFILE [--check --diff] $ARGS
       inventário ad-hoc: -i "<host>,"  (sem arquivo de inventário)

make sandbox
  └─ docker build tests/sandbox/Dockerfile.$DISTRO → docker run (tail -f)
  └─ ansible-playbook … -i "<container>," -c docker -u dev   (comando próprio, sem ANS_FLAGS)
```

O wizard só monta argumentos para o `make`; ele não tem lógica de provisionamento. O Makefile só monta a linha de comando do `ansible-playbook`. Toda a lógica fica em `playbooks/`.

### Modos de conexão

| Modo | Inventário | Conexão | Escalonamento |
|---|---|---|---|
| `local` | `localhost,` | `-c local` | `-K` (senha do sudo) |
| `remote` | `$IP,` | SSH, `-u $USER` | `-K` |
| `tunnel` | `$IP,` | SSH via `ProxyCommand ssh -W` no bastion `$JUMP_USER@$JUMP_IP` | `-K` |
| `sandbox` | nome do container | `-c docker -u dev` | sudo NOPASSWD dentro da imagem |

`remote` e `tunnel` validam o destino na leitura do Makefile (filtrando `MAKECMDGOALS`), então `make local remote` sem `IP` falha antes de rodar qualquer target. Não há default de `IP` (só o `local` usa `localhost`). `IP`, `JUMP_IP` e `JUMP_USER` passam pela função `single_host`: valores vazios, só com espaços, com espaços no meio ou com vírgulas são rejeitados, porque virariam outro inventário em `-i "$(IP),"` ou quebrariam o `ProxyCommand`. O `tunnel` exige os três. Como em qualquer variável do `make`, esses valores também podem vir do ambiente.

`ansible.cfg` define `become = True` / `become_method = sudo` globalmente, e o callback de saída `ansible.builtin.default` com `callback_result_format = yaml`, mais o `ansible.posix.timer` (veja [Collections Ansible necessárias no controlador](#collections-ansible-necessárias-no-controlador)).

## Playbook `site.yml`

Um único play, `hosts: all`, `become: true`, `gather_facts: true`.

`pre_tasks`, todos com tag `always`, então rodam com qualquer `--tags`:

1. `include_vars {{ playbook_dir }}/../profiles/{{ profile }}.yml`: falha se o perfil não existir.
2. `include_vars {{ playbook_dir }}/../profiles/local.yml`, só quando o arquivo existe (`when: … is file or … is link`, avaliado no controller): overrides pessoais, fora do Git. Um `local.yml` que existe mas é inválido (YAML quebrado, conteúdo que não é dicionário, symlink quebrado) faz o play falhar logo no início.
3. `shell: echo $HOME && whoami` com `become: false`, registrado como `real_user_info`. Roda também em check mode.
4. `set_fact user_home` / `user_id`.

`user_home` e `user_id` são o contrato entre o play e as roles: como o play roda como root, qualquer tarefa que escreve no home do usuário usa `become: false` e esses fatos.

Ordem das roles e tags:

| Role | Tags |
|---|---|
| devtools | `devtools`, `packages` |
| languages | `languages` (+ `python`, `node`, `rust`, `go`, `golang` nos includes) |
| docker | `docker` |
| zsh | `zsh`, `shell` |
| ui | `ui`, `visuals`, **`never`** |
| editors | `editors`, `nvim` |
| dotfiles | `dotfiles`, `stow` |

## Camadas de configuração e precedência

Há três fontes de variáveis, todas carregadas com `include_vars`. Entre chamadas de `include_vars`, **a última carregada vence**.

1. `profiles/<profile>.yml`: feature toggles (`*_features`) e pacotes adicionais (`*_extra_packages`, `user_extra_packages`).
2. `profiles/local.yml`: sobrescreve o perfil.
3. `playbooks/roles/<role>/vars/<os_family>.yml`: carregado **dentro da role** (devtools, editors, ui), portanto depois dos perfis.

Consequências:

- Listas base (`devtools_packages`, `editors_packages`, `ui_packages`) vêm sempre do arquivo da distro. Um perfil que as define não tem efeito quando o arquivo da distro existe. A forma suportada de personalizar é `*_extra_packages`.
- O fallback `set_fact … when: X_packages is not defined` só entra quando não existe arquivo de vars para a distro (o `include_vars` tem `failed_when: false`).
- Dicionários são **substituídos, não mesclados** (`hash_behaviour` padrão). Definir `devtools_features: {lazygit: false}` em `local.yml` remove a chave `tpm`, que então assume o `default()` da tarefa.
- Os defaults de features divergem: `devtools_features.*` e `ui_features.*` usam `default(false)`, e `languages_features.*` usa `default(true)`.

`os_family` usado nos nomes de arquivo: `Debian`, `Void`, `RedHat`, `Archlinux`.

## Semântica de tags

Comportamento verificado com ansible-core 2.20:

- As tags declaradas em `roles:` no `site.yml` são herdadas por **todas** as tarefas da role, inclusive as carregadas por `include_tasks`.
- As tags num `include_tasks` se aplicam **só ao include**. As tarefas incluídas precisam repetir a tag para rodar quando aquela tag é selecionada.
- Uma tag que existe só dentro de um arquivo incluído não pode ser selecionada sozinha, porque o include não casa e o arquivo nem é carregado.
- `--list-tags` não mostra tags de tarefas incluídas dinamicamente.
- `ui` tem `never`, então só roda quando uma de suas tags é pedida explicitamente. `TAGS=all` (padrão) não inclui `ui`.

## Roles

### Padrão de instalação resiliente (devtools, editors, ui)

```
include_vars <os_family>.yml (failed_when: false)
set_fact <role>_packages (fallback mínimo, se indefinido)
set_fact _<role>_target_packages = base + *_extra_packages (+ user_extra_packages em devtools)
debug  banner "📌 STATUS" com contagem e lista
block:  package: name=<lista inteira>          # uma transação
rescue: package: name=<item> loop, failed_when: false
        debug para cada pacote que falhou
```

Uma lista com um pacote inexistente não aborta o play: a instalação passa a ser individual e os pacotes ausentes são reportados.

### devtools
- Pacotes CLI por distro.
- `install_lazygit.yml` (quando `devtools_features.lazygit`):
  1. mapeia `ansible_facts.architecture` para o asset do release (`x86_64`, `arm64`, `armv6`);
  2. consulta `api.github.com/…/releases/latest` (com `check_mode: false`);
  3. baixa o asset em um `tempfile` e copia para `/usr/local/bin/lazygit`;
  4. remove o diretório temporário no `always`.
- TPM: `git clone` em `~/.tmux/plugins/tpm` quando `devtools_features.tpm`.

### languages
`main.yml` só tem `include_tasks`, um por linguagem, cada um com sua tag.

| Arquivo | Mecanismo |
|---|---|
| `python.yml` | uv via `curl https://astral.sh/uv/install.sh \| sh` (`UV_INSTALL_DIR=~/.local/bin`, `creates:`), pipx pelo pacote do sistema e `python3 -m pipx ensurepath` |
| `node.yml` | pacote `nodejs` |
| `rust.yml` | `stat` em `~/.cargo/bin/rustup`, depois o instalador oficial `sh.rustup.rs -y --no-modify-path` (`failed_when: false`), com fallback para o pacote `cargo` se o instalador falhar |
| `go.yml` | pacote `golang` (Debian) ou `go` (Void) |

### docker
- `debian.yml`: chave GPG em `/etc/apt/keyrings/docker.asc`, repositório `download.docker.com/linux/<distribution>` com arch mapeada por `docker_apt_arch` (`vars/main.yml`), pacotes `docker-ce`, `docker-ce-cli`, `containerd.io` e plugins buildx e compose. Habilita o serviço se `service_mgr == systemd`.
- `void.yml`: pacote `docker`. Cria o symlink `/etc/sv/docker` → `/var/service/docker` só se os dois caminhos existirem. No Void, o Ansible reporta `service_mgr = service`, não `runit`.
- Para todas as distros: adiciona `user_id` ao grupo `docker`.

### zsh
Pacotes `zsh` e `git`, shell padrão `/bin/zsh` para `user_id`, e `git clone` (branch `master`) de Oh-My-Zsh, Powerlevel10k e dos plugins `zsh-autosuggestions`, `zsh-syntax-highlighting` e `zsh-completions`. Não gera `.zshrc`; isso fica a cargo dos dotfiles.

### ui (opt-in)
Pacotes Sway/Wayland por distro. Se `ui_features.fonts` estiver ativo, baixa a JetBrainsMono Nerd Font (release fixo `v3.0.2`) para `~/.local/share/fonts` e, logo em seguida, roda `fc-cache` só nessa pasta, apenas quando o download rodou (`ui_nerdfont_download` definido e não pulado). É uma task, e não um handler, para rodar logo depois do download sem precisar de `meta: flush_handlers`, que vale para o play inteiro. A condição é `is not skipped`, e não `is changed`, porque `is changed` dispara a regra `no-handler` do ansible-lint. Por isso o `fc-cache` roda sempre que o download roda, mesmo se o `unarchive` não mudou nada (por exemplo, com o zip já parcialmente extraído), o que só custa uma reconstrução de cache a mais.

### editors
Neovim, ferramentas de clipboard (`xclip`, `wl-clipboard`) e `lldb` (exceto Void).

### dotfiles
1. Garante `git` e `stow`.
2. `dotfiles_repos` tem como padrão `[{repo: https://github.com/jozielsc/dotfiles, dest: ~/.dotfiles}]`. Cada item aceita `version` (padrão `main`).
3. Clona ou atualiza cada repositório como o usuário.
4. `stow_repo.yml`: para cada diretório de primeiro nível que não seja oculto, roda `stow --verbose --no-folding --dir=<repo> --target=$HOME <pacote>`.
   - `changed_when`: `LINK:` aparece no stderr.
   - Um conflito (`existing target`) não falha a tarefa: o pacote é pulado e reportado.
   - **Nunca usa `--adopt`**, porque ele moveria os arquivos do `$HOME` para dentro do repositório, sobrescrevendo o conteúdo versionado.

Como `dotfiles` roda por último, qualquer arquivo que roles anteriores criem no `$HOME` dentro do caminho de um pacote stow vira conflito.

## Integrações externas em tempo de execução

| Origem | Usado por | Versão |
|---|---|---|
| `astral.sh/uv/install.sh` | languages/python | latest (curl \| sh) |
| `sh.rustup.rs` | languages/rust | latest (curl \| sh) |
| `api.github.com` + releases `jesseduffield/lazygit` | devtools | latest |
| `github.com/tmux-plugins/tpm` | devtools | `master` |
| `github.com/ohmyzsh/ohmyzsh`, `romkatv/powerlevel10k`, `zsh-users/*` | zsh | `master` |
| `download.docker.com` | docker (Debian) | canal `stable` |
| `github.com/ryanoasis/nerd-fonts` | ui | `v3.0.2` |
| `github.com/jozielsc/dotfiles` | dotfiles | `main` |

Todas exigem acesso à internet a partir do host provisionado.

### Collections Ansible necessárias no controlador

Esta seção é a fonte única dos requisitos do controlador. README e USAGE apenas apontam para cá.

**ansible-core ≥ 2.13.** O mínimo vem do `callback_result_format` (`ansible.cfg`), que surgiu no 2.13. Em versões anteriores, a opção é ignorada sem aviso e a saída volta a ser JSON. Nenhuma checagem em tempo de execução garante esse mínimo (#37). O projeto foi validado só no ansible-core 2.20 (sistema) e 2.21 (ambiente do uv); o 2.13 é o mínimo teórico, não testado.

**Pacote completo `ansible`.** Não há `requirements.yml` (#20). As collections abaixo vêm no pacote `ansible`, mas **não** numa instalação só de `ansible-core` (pip ou pacote `ansible-core` da distro). Nesse caso, instale-as com `ansible-galaxy collection install <nome>`.

Ressalvas por distro do controlador:
- **Ubuntu 22.04 e Debian 11:** o `apt install ansible` instala o Ansible 2.10, abaixo do mínimo: o playbook roda, mas a saída sai em JSON. Use uma versão mais nova (PPA `ppa:ansible/ansible`, `pipx install ansible` ou o ambiente do uv).
- **RHEL 8/9:** o AppStream só tem `ansible-core`. O pacote `ansible` exige o EPEL; sem ele, instale as collections com `ansible-galaxy`.

| Collection | Usada por | Sem ela |
|---|---|---|
| `community.general` | módulo `package` no Void (`xbps`) e no Arch (`pacman`) | **bloqueante**: a instalação de pacotes falha nessas distros (`Could not find a matching action for the "xbps" package manager`) |
| `community.docker` | conexão `-c docker` do `make sandbox` | o sandbox não conecta ao container |
| `ansible.posix` | callback `ansible.posix.timer` (`ansible.cfg`) | opcional: o Ansible só avisa e não mostra o tempo total |

O callback de saída (`ansible.builtin.default`) não depende de collection.

## Matriz de suporte por plataforma

Estado do código na v1.2.1 (2026-10). Atualize esta tabela quando a cobertura mudar.

| Componente | Debian/Ubuntu | Void | RedHat/Fedora | Arch |
|---|---|---|---|---|
| devtools | ✅ | ✅ | ✅ | ✅ |
| python / node / rust | ✅ | ✅ | ✅ | ✅ |
| go | ✅ | ✅ | ❌ sem tarefa | ❌ sem tarefa |
| docker | ✅ repo oficial | ✅ pacote + runit | ❌ sem tarefa de instalação | ❌ sem tarefa de instalação |
| zsh / editors / dotfiles | ✅ | ✅ | ✅ | ✅ |
| ui | ✅ | ✅ | ✅ | ✅ |
| Sandbox Docker | `ubuntu` (24.04) | `void` (glibc) | — | — |

## Testes

- Não há CI. A validação principal é manual pelo sandbox (`make sandbox`).
- Ferramentas de desenvolvimento vêm do grupo `dev` do uv (`pyproject.toml`, `uv.lock`; `uv sync`). O projeto não é um pacote Python (`[tool.uv] package = false`). `make lint` roda `uv run --locked ansible-lint` no repositório inteiro; `make test` roda `uv run --locked molecule test`; `make check` roda os dois em sequência (o test só roda se o lint passar). O `--locked` garante as versões do `uv.lock`. O cenário Molecule ainda não existe (#34) e, quando existir, é **adicional** ao sandbox. Os targets de provisionamento (`local`, `remote`, `tunnel`, `sandbox`) continuam usando o Ansible do sistema, então lint e testes rodam com outro ansible-core e outras collections (#38).
- As imagens do sandbox criam o usuário `dev` com sudo NOPASSWD e mantêm o container vivo com `tail -f /dev/null`. Não há init, então caminhos de serviço (systemd e runit) não são exercitados.
- Para adicionar uma distro ao sandbox, crie `tests/sandbox/Dockerfile.<nome>` com `python3`, `sudo` e o usuário `dev`. O Makefile detecta o arquivo pelo nome.
- Verificações estáticas disponíveis: `ansible-playbook … --syntax-check`, `--list-tasks`, `--list-tags` e `make -n <target>`. `make lint` usa o `ansible-lint` do uv e passa sem falhas (perfil `production`, sem config nem exceções). Variáveis criadas por `register`/`set_fact` dentro de uma role levam o prefixo da role (`devtools_lazygit_release`; `_devtools_lazygit_arch` para fatos internos), como exige a regra `var-naming[no-role-prefix]`.

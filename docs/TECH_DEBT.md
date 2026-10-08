# Baseline Técnica e Dívida Técnica

Levantamento feito em **2026-10-07** sobre a versão **v1.2.1** (commit `e17874c`). É um retrato datado: ao corrigir um item, remova-o ou marque como resolvido com o commit correspondente.

Ambiente de referência da análise: ansible-core 2.20.0, community.general 11.4.1.

O backlog oficial são as Issues do GitHub, no Project #6 (veja [WORKFLOW.md](WORKFLOW.md)). Cada item rastreado leva o número da sua Issue (`#<n>`). O épico de suporte a RedHat/Arch é a Issue #6 (não confundir com o Project #6).

Legenda de evidência:
- **Confirmado**: verificado por `make -n`, `--syntax-check`/`--list-tasks`, teste isolado ou leitura sem ambiguidade do código.
- **Provável**: deduzido do código e da documentação dos módulos, sem execução real.
- **A verificar**: hipótese que precisa ser reproduzida no sandbox.

## Bugs e comportamentos incorretos

| # | Item | Onde | Evidência | Issue |
|---|---|---|---|---|
| B1 | `make remote` sem `IP=` roda contra `localhost` via SSH: o `IP ?= localhost` deixa o `ifndef IP` sem efeito | `Makefile` | Confirmado (`make -n remote`) | #11 |
| B2 | `make sandbox` ignora `DRY=1` (monta um comando próprio sem `ANS_FLAGS`), mas o wizard oferece dry-run para o sandbox | `Makefile`, `scripts/interactive.sh` | Confirmado (`make -n sandbox DRY=1`) | #12 |
| B3 | Em RedHat e Arch, a role docker não instala nada e depois tenta adicionar o usuário ao grupo `docker`, que não existe | `roles/docker/tasks/main.yml` | Confirmado (leitura) | #7 |
| B4 | Go não é instalado em RedHat nem Arch, sem aviso | `roles/languages/tasks/go.yml` | Confirmado (leitura) | #8 |
| B5 | Nome do pacote pipx divergente: `python.yml` usa `python3-pipx` para Debian, `devtools/vars/Debian.yml` usa `pipx`. O `failed_when: false` esconde a falha | `python.yml`, `devtools/vars/Debian.yml` | Confirmado (divergência); pacote inexistente: Provável | #14 |
| B6 | Tags `uv` e `pipx` não funcionam sozinhas, porque o include só tem a tag `python` | `roles/languages/tasks/` | Confirmado (teste de herança de tags) | #15 |
| B7 | Tarefas "📌 STATUS" de node, rust e go não têm tag própria e não aparecem com `--tags node/rust/go` | `roles/languages/tasks/` | Confirmado | #15 |
| B8 | No wizard, desmarcar todos os componentes resulta em `TAGS=all` | `scripts/interactive.sh` (passo 6) | Confirmado (leitura) | #16 |
| B9 | `make local DRY=1` deve falhar no Lazygit: `tempfile` não suporta check mode (é pulado), então `lazygit_temp.path` fica indefinido no `unarchive` | `install_lazygit.yml` | Provável | #13 |
| B10 | A mensagem diz "Node.js e NPM", mas `npm` é um pacote separado em Debian e Arch e não é instalado | `node.yml` | Provável | #17 |
| B11 | O instalador do uv e o `pipx ensurepath` podem alterar `~/.bashrc`, `~/.zshrc` e `~/.profile` antes do stow, gerando conflitos que fazem pacotes de dotfiles serem pulados | `python.yml` + `dotfiles` | A verificar | #18 |

## Inconsistências de configuração

- Um perfil não consegue substituir as listas base de pacotes, porque o arquivo de vars da distro é carregado depois (ver [ARCHITECTURE.md](ARCHITECTURE.md#camadas-de-configuração-e-precedência)). `profiles/local.sample.yml` não deixa isso claro. (#19)
- Dicionários `*_features` são substituídos, não mesclados. Os defaults divergem: `default(false)` em devtools e ui, `default(true)` em languages. (#19)
- `profiles/local.yml` ausente gera um erro vermelho no output (`ignore_errors`). Com `PROFILE=local`, o arquivo é carregado duas vezes. (#19)
- `-K` é sempre passado em `local`, `remote` e `tunnel`, mesmo com `USER=root`. (#20)
- O alvo `help` do Makefile não lista as tags `editors` e `ui`. (#25)
- As listas de pacotes divergem entre distros: Debian e RedHat não têm `delta`, `broot`, `tree-sitter` nem `kubectl`. Void não tem `lldb`. No Debian, `fd` e `bat` ficam como `fdfind` e `batcat`, sem alias. (#21)
- O repositório Docker usa `distribution | lower`, o que quebra em derivados do Ubuntu e do Debian (Mint, Pop!_OS). (#22)
- `fc-cache` (ui) depende de fontconfig, que não está na lista de pacotes. (#23)

## Duplicações

- O bloco de instalação resiliente e o banner de status estão copiados em `devtools`, `editors` e `ui` (cerca de 45 linhas cada). (#24)
- O carregamento de vars por distro e o fallback estão repetidos nas mesmas três roles. (#24)
- `languages_features.<x> | default(true)` está repetido em cada tarefa, em vez de ficar no include. (#15)
- A lista de tags existe em 6 lugares: `site.yml`, `help` do Makefile, wizard, README (PT e EN), `USAGE.md`, e também no `CLAUDE.md`. (#25)
- As listas de pacotes são 4 distros × 3 roles mantidas à mão, sem uma tabela única de nomes canônicos. (#21)

## Reprodutibilidade e cadeia de suprimentos

- `curl | sh` sem checksum (uv, rustup). (#26)
- Lazygit consulta `releases/latest` na API do GitHub a cada execução: rate limit de 60 req/h sem token, e baixa de novo mesmo quando já está instalado. (#13)
- Oh-My-Zsh, p10k, plugins e TPM usam `master` com update a cada execução, então o resultado não é reproduzível e há `changed` em execuções repetidas. (#26)
- O repositório de dotfiles padrão é pessoal (`jozielsc/dotfiles`). (sem Issue: escolha de design do mantenedor)

## Ferramentas e qualidade

- `stdout_callback = yaml` (`community.general.yaml`) está deprecated, com remoção no community.general 12.0.0. A alternativa é `callback_result_format = yaml` no callback `default`. (#27)
- `make deps` referencia um `requirements.yml` que não existe. (#20)
- `make lint` cobre só `playbooks/*.yml` e depende do `ansible-lint`. Não há config de lint nem `shellcheck` para o wizard. (#28)
- Não há CI, testes de idempotência (rodar duas vezes e conferir `changed=0`) nem verificação depois do provisionamento. (#28, #29)
- O sandbox só tem Void e Ubuntu e não tem init, então RedHat, Arch e os caminhos de serviço não são testados. (#9, #29)
- Não há checagem de distro suportada no início do play. Uma distro desconhecida cai nos fallbacks mínimos sem aviso. (#10)

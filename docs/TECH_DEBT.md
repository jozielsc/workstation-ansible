# Baseline Técnica e Dívida Técnica

Comportamentos problemáticos e limitações **atuais** do sistema, levantados em **2026-10-07** sobre a versão **v1.2.1** (commit `e17874c`). Este documento descreve o que o código faz hoje. O que precisa ser feito, e como, fica só na Issue indicada em cada item. Quando um item for resolvido, remova-o no mesmo PR, para que nada aqui descreva comportamento obsoleto.

Ambiente de referência da análise: ansible-core 2.20.0, community.general 11.4.1.

O backlog oficial são as Issues do GitHub, no Project #6 (veja [WORKFLOW.md](WORKFLOW.md)). Cada item rastreado leva o número da sua Issue (`#<n>`). O épico de suporte a RedHat/Arch é a Issue #6 (não confundir com o Project #6).

Legenda de evidência:
- **Confirmado**: verificado por `make -n`, `--syntax-check`/`--list-tasks`, teste isolado ou leitura sem ambiguidade do código.
- **Provável**: deduzido do código e da documentação dos módulos, sem execução real.
- **A verificar**: hipótese que precisa ser reproduzida no sandbox.

## Bugs e comportamentos incorretos

| # | Item | Onde | Evidência | Issue |
|---|---|---|---|---|
| B2 | `make sandbox` ignora `DRY=1` (monta um comando próprio sem `ANS_FLAGS`), mas o wizard oferece dry-run para o sandbox | `Makefile`, `scripts/interactive.sh` | Confirmado (`make -n sandbox DRY=1`) | #12 |
| B3 | Em RedHat e Arch, a role docker não instala nada e depois tenta adicionar o usuário ao grupo `docker`, que não existe | `roles/docker/tasks/main.yml` | Confirmado (leitura) | #7 |
| B4 | Go não é instalado em RedHat nem Arch, sem aviso | `roles/languages/tasks/go.yml` | Confirmado (leitura) | #8 |
| B5 | Nome do pacote pipx divergente: `python.yml` usa `python3-pipx` para Debian, `devtools/vars/Debian.yml` usa `pipx`. O `failed_when: false` esconde a falha | `python.yml`, `devtools/vars/Debian.yml` | Confirmado (divergência); pacote inexistente: Provável | #14 |
| B6 | Tags `uv` e `pipx` não funcionam sozinhas, porque o include só tem a tag `python` | `roles/languages/tasks/` | Confirmado (teste de herança de tags) | #15 |
| B7 | Tarefas "📌 STATUS" de node, rust e go não têm tag própria e não aparecem com `--tags node/rust/go` | `roles/languages/tasks/` | Confirmado | #15 |
| B8 | No wizard, desmarcar todos os componentes resulta em `TAGS=all` | `scripts/interactive.sh` (passo 6) | Confirmado (leitura) | #16 |
| B10 | A mensagem diz "Node.js e NPM", mas `npm` é um pacote separado em Debian e Arch e não é instalado | `node.yml` | Confirmado no Arch (sandbox `arch`, #9) | #17 |
| B11 | O instalador do uv e o `pipx ensurepath` podem alterar `~/.bashrc`, `~/.zshrc` e `~/.profile` antes do stow, gerando conflitos que fazem pacotes de dotfiles serem pulados | `python.yml` + `dotfiles` | A verificar | #18 |
| B12 | `USER ?= $(shell whoami)` nunca vale, porque `USER` sempre existe no ambiente: `remote`/`tunnel` usam o `$USER` do shell como usuário SSH, e a doc o apresenta como opcional | `Makefile` | Confirmado (`make -n remote IP=x`) | #35 |
| B13 | Um pacote de dotfiles com conflito reporta `changed` sem alterar nada: com `--verbose`, o stow imprime os `LINK:` planejados antes de abortar, e o `changed_when` só procura `LINK: `. Com um conflito, a execução nunca chega a `changed=0`. Além disso, o `failed_when` aceita qualquer rc != 0 com `BUG` no stderr, e o relatório só mostra `existing target`: um erro interno do stow deixa o pacote sem aplicar e o play termina verde, sem aviso | `dotfiles/tasks/stow_repo.yml` | `changed`: Confirmado (sandbox void); `BUG`: Confirmado (leitura) | #39 |
| B16 | No modo `cli`, o `tui_yesno` (passos 5 e 6 do wizard) não segue as regras dos outros prompts: o resumo da confirmação sai numa linha só, com `\n` literais (`read -p` não interpreta escapes); qualquer resposta que começa com `b`/`c` navega (ex.: `bruno` volta); e no passo 5 `c` conta como "não" e segue para o passo 6 em vez de cancelar | `scripts/interactive.sh` (`tui_yesno`) | Confirmado (`bash -x` em modo `cli`) | #48 |
| B17 | No modo `local`, Back no passo 3 do wizard reabre o passo 3: o passo 2 não tem caso para `local` e devolve para o 3, então só dá para voltar ao passo 1 cancelando | `scripts/interactive.sh` (passos 2 e 3) | Confirmado (modo `cli`) | #49 |
| B18 | `make sandbox` apaga e recria o container a cada chamada (`docker rm -f` + `docker run`), apesar da mensagem "Garantindo que o container … esteja rodando": uma segunda execução pelo `make` provisiona um container limpo, então a idempotência pedida pela Definição de pronto não é testável por ele | `Makefile` (target `sandbox`) | Confirmado (sandbox void, #13) | #51 |
| B19 | Em check mode (`DRY=1`), num Debian/Ubuntu sem `python3-apt`, a instalação em lote falha (`python3-apt must be installed to use check mode`), cai no `rescue` e a instalação individual reporta todos os pacotes como `ok`, porque o `failed_when: false` esconde a mesma falha: a simulação não mostra o que seria instalado | `devtools`, `editors`, `ui` (instalação resiliente) | Confirmado (sandbox ubuntu, `devtools`) | #52 |
| B20 | As roles que instalam pacotes não atualizam o índice do gerenciador (só `docker/tasks/debian.yml` usa `update_cache`): no Arch e no Void com o sync DB velho, ou numa imagem do sandbox reaproveitada do cache de camadas, a instalação em lote falha com 404 e o `rescue` deixa os pacotes faltando só com avisos | `devtools`, `editors`, `ui`, `languages` | Provável (leitura; revisão do PR #54) | #55 |
| B21 | No Fedora ≥ 41 (dnf5), o módulo `package` precisa do `python3-libdnf5` no alvo, e nada no play o instala: num Fedora Server/Cloud/minimal sem ele, toda instalação de pacote falha. A imagem do sandbox `fedora` instala o pacote no Dockerfile, então o sandbox não reproduz a falha | `playbooks/site.yml`, `tests/sandbox/Dockerfile.fedora` | Provável (leitura; revisão do PR #54) | #56 |

## Inconsistências de configuração

- Um perfil não consegue substituir as listas base de pacotes, porque o arquivo de vars da distro é carregado depois (ver [ARCHITECTURE.md](ARCHITECTURE.md#camadas-de-configuração-e-precedência)). `profiles/local.sample.yml` não deixa isso claro. (#19)
- Dicionários `*_features` são substituídos, não mesclados. Os defaults divergem: `default(false)` em devtools e ui, `default(true)` em languages. (#19)
- Com `PROFILE=local`, o `profiles/local.yml` é carregado duas vezes. (#19)
- `-K` é sempre passado em `local`, `remote` e `tunnel`, mesmo com `USER=root`. (#20)
- O alvo `help` do Makefile não lista as tags `editors` e `ui`. (#25)
- As listas de pacotes divergem entre distros: Debian e RedHat não têm `delta`, `broot`, `tree-sitter` nem `kubectl`. Void não tem `lldb`. No Debian, `fd` e `bat` ficam como `fdfind` e `batcat`, sem alias. (#21)
- O repositório Docker usa `distribution | lower`, o que quebra em derivados do Ubuntu e do Debian (Mint, Pop!_OS). (#22)
- A fonte da role `ui` depende de fontconfig (`fc-cache`) e de `unzip` (extração do zip), que não estão nas listas de pacotes da `ui`. O `unzip` vem da `devtools`, então `TAGS=ui` sozinho falha numa instalação mínima (confirmado no sandbox `void` e `ubuntu`). (#23)

## Duplicações

- O bloco de instalação resiliente e o banner de status estão copiados em `devtools`, `editors` e `ui` (cerca de 45 linhas cada). (#24)
- O carregamento de vars por distro e o fallback estão repetidos nas mesmas três roles. (#24)
- `languages_features.<x> | default(true)` está repetido em cada tarefa, em vez de ficar no include. (#15)
- A lista de tags existe em 6 lugares: `site.yml`, `help` do Makefile, wizard, README (PT e EN), `USAGE.md`, e também no `CLAUDE.md`. (#25)
- As listas de pacotes são 4 distros × 3 roles mantidas à mão, sem uma tabela única de nomes canônicos. (#21)

## Reprodutibilidade e cadeia de suprimentos

- `curl | sh` sem checksum (uv, rustup). (#26)
- Lazygit consulta `releases/latest` na API do GitHub a cada execução (rate limit de 60 req/h sem token), porque a versão desejada é sempre a última; o download só acontece quando não há binário ou o instalado é mais antigo. (#26)
- Oh-My-Zsh, p10k, plugins e TPM usam `master` com update a cada execução, então o resultado não é reproduzível e há `changed` em execuções repetidas. (#26)
- O repositório de dotfiles padrão é pessoal (`jozielsc/dotfiles`). (sem Issue: escolha de design do mantenedor)

## Ferramentas e qualidade

- `make deps` referencia um `requirements.yml` que não existe. (#20)
- As collections não são declaradas em lugar nenhum, e o `community.general` é dependência implícita no Void e no Arch. Detalhes em [ARCHITECTURE.md](ARCHITECTURE.md#collections-ansible-necessárias-no-controlador). (#20)
- O CI só roda o `make lint`. Não há CI do provisionamento, testes de idempotência (rodar duas vezes e conferir `changed=0`) nem verificação depois do provisionamento. (#29)
- O sandbox não tem init, então os caminhos de serviço (systemd e runit) não são testados, e as distros só rodam manualmente. (#29)
- Não há checagem de distro suportada no início do play. Uma distro desconhecida cai nos fallbacks mínimos sem aviso. (#10)

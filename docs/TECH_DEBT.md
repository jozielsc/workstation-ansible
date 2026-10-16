# Baseline Técnica e Dívida Técnica

Comportamentos problemáticos e limitações **atuais** do sistema, levantados em **2026-10-07** sobre a versão **v1.2.1** (commit `e17874c`). Este documento descreve o que o código faz hoje. O que precisa ser feito, e como, fica só na Issue indicada em cada item. Quando um item for resolvido, remova-o no mesmo PR, para que nada aqui descreva comportamento obsoleto.

Ambiente de referência da análise: ansible-core 2.20.0, community.general 11.4.1.

O backlog oficial são as Issues do GitHub, no Project #6 (veja [WORKFLOW.md](WORKFLOW.md)). Cada item rastreado leva o número da sua Issue (`#<n>`). O épico de suporte a RedHat/Arch é a Issue #6 (não confundir com o Project #6).

Legenda de evidência:
- **Confirmado**: verificado pelo `--print` do `scripts/workstation.sh` (ou, antes da #67, pela simulação do antigo executor de tarefas), `--syntax-check`/`--list-tasks`, teste isolado ou leitura sem ambiguidade do código.
- **Provável**: deduzido do código e da documentação dos módulos, sem execução real.
- **A verificar**: hipótese que precisa ser reproduzida no sandbox.

## Bugs e comportamentos incorretos

| # | Item | Onde | Evidência | Issue |
|---|---|---|---|---|
| B6 | Tags `uv` e `pipx` não funcionam sozinhas, porque o include só tem a tag `python` | `roles/languages/tasks/` | Confirmado (teste de herança de tags) | #15 |
| B7 | Tarefas "📌 STATUS" de node, rust e go não têm tag própria e não aparecem com `--tags node/rust/go` | `roles/languages/tasks/` | Confirmado | #15 |
| B11 | O instalador do uv e o `pipx ensurepath` podem alterar `~/.bashrc`, `~/.zshrc` e `~/.profile` antes do stow, gerando conflitos que fazem pacotes de dotfiles serem pulados | `python.yml` + `dotfiles` | A verificar | #18 |
| B13 | Um pacote de dotfiles com conflito reporta `changed` sem alterar nada: com `--verbose`, o stow imprime os `LINK:` planejados antes de abortar, e o `changed_when` só procura `LINK: `. Com um conflito, a execução nunca chega a `changed=0`. Além disso, o `failed_when` aceita qualquer rc != 0 com `BUG` no stderr, e o relatório só mostra `existing target`: um erro interno do stow deixa o pacote sem aplicar e o play termina verde, sem aviso | `dotfiles/tasks/stow_repo.yml` | `changed`: Confirmado (sandbox void); `BUG`: Confirmado (leitura) | #39 |
| B19 | Em check mode (`--dry-run`), num Debian/Ubuntu sem `python3-apt`, a instalação em lote falha (`python3-apt must be installed to use check mode`), cai no `rescue` e a instalação individual reporta todos os pacotes como `ok`, porque o `failed_when: false` esconde a mesma falha: a simulação não mostra o que seria instalado | `devtools`, `editors`, `ui` (instalação resiliente) | Confirmado (sandbox ubuntu, `devtools`) | #52 |
| B20 | As roles que instalam pacotes não pedem a atualização do índice do gerenciador (só `docker/tasks/debian.yml` usa `update_cache`). No Void isso não falta: o módulo `xbps` sincroniza o índice por padrão (`update_cache: true`). No Arch com o sync DB velho, ou numa imagem do sandbox `arch` reaproveitada do cache de camadas, a instalação falha com 404 e o `rescue` deixa os pacotes faltando só com avisos | `devtools`, `editors`, `ui`, `languages`, `docker` (Arch e RedHat) | Confirmado no Arch (sandbox `arch`, 2026-10-15, PR #81); Void descartado (padrão do módulo `xbps`); Fedora: Provável | #55 |
| B24 | No RedHat/Fedora, o `docker-ce`/`containerd.io` do repositório oficial conflitam com `moby-engine`, `podman-docker` e `runc` (container-tools); com um deles instalado, o dnf recusa a transação e o play para na role `docker` | `roles/docker/tasks/redhat.yml` | Provável (leitura; revisão do PR #59) | #60 |

## Inconsistências de configuração

- Um perfil não consegue substituir as listas base de pacotes, porque o arquivo de vars da distro é carregado depois (ver [ARCHITECTURE.md](ARCHITECTURE.md#camadas-de-configuração-e-precedência)). `profiles/local.sample.yml` não deixa isso claro. (#19)
- Dicionários `*_features` são substituídos, não mesclados. Os defaults divergem: `default(false)` em devtools e ui, `default(true)` em languages. (#19)
- Com `--profile local`, o `profiles/local.yml` é carregado duas vezes. (#19)
- `-K` é sempre passado em `local`, `remote` e `tunnel`, mesmo com `--user root`. (#20)
- As listas de pacotes divergem entre distros: Debian e RedHat não têm `delta`, `broot`, `tree-sitter` nem `kubectl`. No Debian, `fd` e `bat` ficam como `fdfind` e `batcat`, sem alias. (#21)
- O repositório Docker usa `distribution | lower`, o que quebra em derivados do Ubuntu e do Debian (Mint, Pop!_OS). (#22)
- A fonte da role `ui` depende de fontconfig (`fc-cache`) e de `unzip` (extração do zip), que não estão nas listas de pacotes da `ui`. O `unzip` vem da `devtools`, então `--tags ui` sozinho falha numa instalação mínima (confirmado no sandbox `void` e `ubuntu`). (#23)

## Duplicações

- O bloco de instalação resiliente e o banner de status estão copiados em `devtools`, `editors` e `ui` (cerca de 45 linhas cada). (#24)
- O carregamento de vars por distro e o fallback estão repetidos nas mesmas três roles. (#24)
- `languages_features.<x> | default(true)` está repetido em cada tarefa, em vez de ficar no include. (#15)
- A lista de tags existe em 6 lugares: `site.yml`, `help` do `scripts/workstation.sh`, wizard, README (PT e EN), `USAGE.md`, e também no `CLAUDE.md`. (#25)
- As listas de pacotes são 4 distros × 3 roles mantidas à mão, sem uma tabela única de nomes canônicos. (#21)

## Reprodutibilidade e cadeia de suprimentos

- `curl | sh` sem checksum (uv, rustup). (#26)
- Lazygit consulta `releases/latest` na API do GitHub a cada execução (rate limit de 60 req/h sem token), porque a versão desejada é sempre a última; o download só acontece quando não há binário ou o instalado é mais antigo. (#26)
- Oh-My-Zsh, p10k, plugins e TPM usam `master` com update a cada execução, então o resultado não é reproduzível e há `changed` em execuções repetidas. (#26)
- O repositório de dotfiles padrão é pessoal (`jozielsc/dotfiles`). (sem Issue: escolha de design do mantenedor)

## Ferramentas e qualidade

- Não há como instalar as collections pelo projeto: o antigo comando `deps` referenciava um `requirements.yml` que não existe e foi removido na #67, sem substituto. (#20)
- As collections não são declaradas em lugar nenhum, e o `community.general` é dependência implícita no Void e no Arch. Detalhes em [ARCHITECTURE.md](ARCHITECTURE.md#collections-ansible-necessárias-no-controlador). (#20)
- O CI só roda o `just lint`. Não há CI do provisionamento, testes de idempotência (rodar duas vezes e conferir `changed=0`) nem verificação depois do provisionamento. (#29)
- O sandbox não tem init, então os caminhos de serviço (systemd e runit) não são testados, e as distros só rodam manualmente. (#29)

# Workstation Ansible - Arquitetura

Documento de referência técnica para quem vai modificar o projeto. Para uso do dia a dia, veja [USAGE.md](USAGE.md). Problemas conhecidos e dívida técnica estão em [TECH_DEBT.md](TECH_DEBT.md).

## Visão geral do fluxo

```
scripts/workstation.sh  (sem comando)
  └─ bash scripts/interactive.sh   wizard TUI (dialog > whiptail > CLI puro)
       └─ scripts/workstation.sh <modo> --profile … --tags … [--dry-run] [--distro … | --ip … --user … --jump-ip … --jump-user …]

scripts/workstation.sh local | remote | tunnel
  └─ ansible-playbook playbooks/site.yml -K --tags <tags> -e profile=<perfil> [--check --diff] [args depois de --]
       inventário ad-hoc: -i "<host>,"  (sem arquivo de inventário)

scripts/workstation.sh sandbox
  └─ docker build tests/sandbox/Dockerfile.<distro> → docker rm -f (container anterior) → docker run (tail -f)
  └─ ansible-playbook … -i "<container>," -c docker -u dev   (sem -K; com --dry-run, --check --diff)
```

O `workstation.sh` da raiz é só um atalho: um wrapper que repassa todos os argumentos ao `scripts/workstation.sh` com `exec bash` (sem depender da permissão de execução do script de `scripts/`), informando em `WORKSTATION_PROG` o caminho com que foi chamado. O wizard só monta argumentos para o `scripts/workstation.sh`; ele não tem lógica de provisionamento. O script só valida as opções e monta a linha de comando do `ansible-playbook` (e do `docker`, no sandbox). Toda a lógica de provisionamento fica em `playbooks/`.

O `scripts/workstation.sh` tem uma função por comando (`run_local`, `run_remote`, `run_tunnel`, `run_sandbox`, `run_sandbox_shell`, `run_sandbox_clean`), e `ansible_cmd` monta o `ansible-playbook` de todos eles (o sandbox o chama sem `-K`). As opções aceitam `--opção valor` e `--opção=valor`; um valor que começa com `-` só vale na segunda forma, para que `--tags --dry-run` não use `--dry-run` como tag (o wizard sempre usa a segunda forma, para que um valor digitado com `-` chegue à validação). Uma opção desconhecida, uma opção com valor vazio, uma opção que não se aplica ao comando (por exemplo, `--ip` com `local`), um segundo comando ou argumentos depois de `--` num comando que não roda o `ansible-playbook` encerram com código 2. `-h`/`--help` mostra a ajuda em qualquer posição, depois de conferir o comando e as opções: `bogus --help` e `local --ip x --help` também encerram com código 2. O `--profile` precisa ser um nome simples (letras, números e `.`, `_`, `-`, a mesma regra `NAME_RE` dos hosts) com um arquivo `profiles/<nome>.yml`: ele vira `-e profile=<nome>`, que o Ansible lê como uma lista key=value separada por espaços, então `--profile 'default x=y'` definiria outra variável. `run_cmd` mostra cada comando antes de executá-lo, com aspas simples nos argumentos que precisam delas (`shell_join`, em `scripts/lib/quote.sh`, que o wizard usa para montar o comando do resumo); com `--print`, só mostra (as mensagens de progresso somem). O script tem shebang `bash`: o shell de quem chama (bash ou zsh) não interfere. Ele resolve o próprio caminho com `readlink -f`, então também funciona chamado por um symlink (por exemplo, `~/bin/ws`); onde o `readlink` não tem `-f` (macOS antes do 12.3), usa o caminho da chamada, que funciona sem symlink. Ele exporta `ANSIBLE_FORCE_COLOR=1` e `PYTHONUNBUFFERED=1`. Sem comando, ele chama o wizard com `bash`.

O script funciona chamado de qualquer pasta e **não** muda de pasta: caminhos relativos depois de `--` (`-e @vars.yml`, `--vault-password-file`) continuam relativos à pasta de quem chama. Por isso o playbook e o `tests/sandbox/` entram com caminho absoluto, e o `ansible.cfg` do projeto vai no próprio comando, como `env ANSIBLE_CONFIG=<repo>/ansible.cfg ansible-playbook …` (um `ANSIBLE_CONFIG` já definido continua valendo, como valia antes sobre o `ansible.cfg` da pasta atual). Assim, o comando que o `--print` mostra funciona colado em qualquer pasta. As mensagens, as sugestões do sandbox e o resumo do wizard mostram o script pelo caminho com que ele foi chamado (`WORKSTATION_PROG`, quando o atalho da raiz o informa, ou `$0`; o caminho é repassado ao wizard na mesma variável, que só muda o texto exibido, nunca o que é executado. O script lê a variável e a remove do ambiente, então ela não chega ao `ansible-playbook` nem ao `docker`; um `WORKSTATION_PROG` já definido no shell do usuário também muda o nome exibido; um nome sem `/` que existe na pasta atual, como em `bash workstation.sh`, vira `./workstation.sh`); com o wizard chamado direto, pelo caminho absoluto.

As tarefas de desenvolvimento (`lint`, `test`, `check` e um atalho para o `sandbox`) ficam no `justfile` e rodam com o `just` do grupo `dev` do uv (`uv run just <receita>`; veja [Testes](#testes)). Quem só provisiona não precisa do uv nem do just.

### Wizard e camada de interface

O wizard escolhe a interface pela ordem `dialog` > `whiptail` > `cli` (texto puro, quando não há nenhum dos dois). `ui_init` monta essa lista em `UI_ENGINES`, sempre com o `cli` no fim. Se stdin ou stdout não for um terminal, o `dialog` e o `whiptail` não funcionam: `ui_init` avisa uma vez e deixa só o `cli`. `TUI_ENGINE=dialog|whiptail|cli` força um motor, **sem fallback**, para quem quer usar ou testar um motor específico não acabar em outro sem perceber. Um valor inválido, um motor que não está instalado, a falta de terminal para `dialog`/`whiptail` ou uma falha do motor no meio do wizard encerram com código 1 e uma mensagem. `ui_init` também cria o diretório dos temporários (`UI_TMP_DIR`: o stderr do motor e o texto do help), removido por `trap` na saída, inclusive no Ctrl-C.

Os passos de `main` não conhecem o motor: eles chamam `ui_menu`, `ui_checklist`, `ui_input`, `ui_yesno` e `ui_text` e leem `UI_ACTION` (`ok`, `no` (só no sim/não), `back` ou `cancel`), `UI_VALUE` (item escolhido ou texto digitado) e `UI_LIST` (itens marcados). Essas funções não são chamadas com `$(...)`: o resultado volta por variáveis globais, para que a troca de motor depois de um erro valha para o resto do wizard. `ui_dialog` despacha cada chamada para o adaptador do motor atual:

- **`dialog`**: Back é o `--extra-button` (código 3), Cancel é o código 1 e Esc é 255. No sim/não, o código 1 é "não", então o sim/não com Back ganha um quarto botão, Cancel (`--help-button`, código 2): os botões ficam Yes, Back, No e Cancel.
- **`whiptail`**: só tem dois botões por diálogo, e o do Fedora (newt 0.52.25) ignora o Esc. Nas telas com Back, o segundo botão vira "Voltar/Cancelar" e abre um menu: voltar à tela anterior, cancelar o wizard ou continuar nesta tela. O sim/não com Back vira um menu Yes/No com esse mesmo botão. A altura da caixa de sim/não (nos dois motores) cresce com o texto, para o resumo da confirmação caber, até a altura do terminal; acima disso, o texto rola. Onde o Esc funciona (Debian/Ubuntu), ele cancela, como no `dialog`. Limitação: "continuar nesta tela" reabre o diálogo com os valores de quando ele foi aberto, porque com o segundo botão o `whiptail` não devolve o que foi editado (código 1 e saída vazia; verificado no newt 0.52.25). O Cancel do `dialog` também descarta a edição, mas encerra o wizard.
- **`cli`**: só `b` e `c` sozinhos navegam, então um valor como `bruno` passa. `b` (Back) só vale onde há a opção Back, e `c` (Cancel) vale em todos os passos. O fim da entrada (Ctrl-D) sem nada digitado também cancela, como o Esc. Sem terminal em stdin, o fim da entrada não é uma ação do usuário (as respostas acabaram), e o wizard sai com código 1 e uma mensagem. O texto dos diálogos é impresso sem interpretar escapes: só as sequências `\n` viram quebra de linha, como no dialog/whiptail, para que um `\c` ou `\033` num valor digitado (que aparece no resumo da confirmação) não corte o resumo nem vire sequência de terminal. No help, o Ctrl-C vai para o `less` (por exemplo, para abortar uma busca) e não encerra o wizard. No sim/não, só uma resposta que começa com `y` confirma; qualquer outra, inclusive Enter vazio, é "não". Entrada vazia mantém o item atual do menu (o marcado `ON`, como no radiolist do dialog/whiptail) ou confirma a seleção do checklist. No checklist, cada entrada válida inverte os itens indicados e mostra a lista de novo, até o Enter vazio; um valor seguido do fim da entrada é aplicado e confirma. Qualquer outra entrada inválida mostra uma mensagem e pergunta de novo. A conversão de número para item (`parse_index`) lê em base 10 (`08` é o item 8) e recusa mais de 9 dígitos significativos.

O `dialog` e o `whiptail` rodam por `ui_tui_exec`. O valor sai por `--output-fd 3`, a tela vai para o terminal e o stderr vai para um arquivo em `UI_TMP_DIR`, então uma mensagem de erro do motor não se mistura ao valor. O motor falhou quando sai com um código fora de 0/1/2/3/255, ou quando sai com código diferente de 0 e escreve no stderr. Esse último critério é necessário porque o `whiptail` sai com 1 numa opção inválida, igual ao Cancel. Numa falha, `ui_engine_failed` mostra a mensagem, tira o motor de `UI_ENGINES` e o mesmo diálogo é repetido no próximo motor, no mesmo passo e com as escolhas preservadas (com `TUI_ENGINE`, encerra com código 1). Uma falha só na tela de texto (o help, por exemplo com o terminal pequeno demais para a caixa) não troca de motor: o texto é mostrado no modo `cli` dessa vez e os outros passos continuam no motor atual. O `cli` é o último da lista e não é trocado: num terminal, o wizard termina por uma ação do usuário; sem terminal, também quando as respostas do stdin acabam (código 1).

Em `main`, a navegação segue uma lista linear de telas. `wizard_screens` monta essa lista a cada volta do laço, a partir do modo atual: `target`, os campos do modo (`distro` no `sandbox`; `remote_ip` e `remote_user` no `remote`; os mesmos dois mais `jump_ip` e `jump_user` no `tunnel`, onde `remote_ip`/`remote_user` só mudam o título; nenhum no `local`), `profile`, `tags`, `dry_run` e `confirm`. `main` guarda só a posição (`pos`) na lista. `screen_nav` trata a ação de cada diálogo: `ok` avança uma tela, `back` volta uma e qualquer outra ação cancela. Como a lista só tem as telas que o modo mostra, o Back sempre leva à última tela vista, inclusive entre os campos do modo. Um modo sem campos não precisa de caso especial em outra tela. A simulação trata antes as respostas do sim/não. A confirmação tem um tratamento próprio, porque ali "No" e Cancel encerram com a mensagem "Provisioning cancelled by user.". O passo de componentes (`tags`) trata um `ok` com a lista vazia: avisa e reabre o próprio passo, em vez de avançar, porque a confirmação monta o `--tags` a partir dessa lista; sem terminal na entrada (respostas pelo stdin), ele para com erro. Uma tela da lista sem `case` em `main` encerra o wizard com erro, em vez de ser pulada em silêncio (o Back não conseguiria passar dela). Para adicionar uma tela: inclua-a em `wizard_screens` (num passo próprio, ou entre os campos do modo, que formam um passo só) e crie o `case` dela em `main`.

Os títulos (`step_title`) numeram os passos da lista do modo atual, sem a confirmação. `wizard_screens` monta a lista a partir de passos (cada passo é uma ou mais telas; os campos do modo, definidos num lugar só, formam o passo 2) e guarda o número do passo de cada tela em `screen_numbers` e o total em `step_total`; `step_title` lê o número da tela atual (`screens[pos]`). Por isso o modo `local`, que não tem campos, tem 4 passos e os outros têm 5 (por exemplo, "Step 2/5: Bastion Username", ou "Step 2/4: Profile Selection" no `local`). A escolha do modo mostra só "Step 1", porque o total depende do modo que ainda vai ser escolhido. Como o número muda com o modo, os docs citam as telas pelo nome (simulação, confirmação), não pelo número.

Para adicionar um motor: inclua-o na detecção de `ui_init` e no `case` de `TUI_ENGINE`, e traduza as ações dele em `ui_tui` (se ele seguir a interface do dialog/whiptail) ou num adaptador próprio, como os `ui_cli_*`, chamado por `ui_dialog`. Os passos de `main` não mudam.

O wizard exige bash ≥ 4.4: ele roda com `set -u`, e expandir um array vazio (`"${UI_LIST[@]}"` e `"${selected_tags_array[@]}"` quando todos os componentes são desmarcados) falha como variável não definida em versões anteriores.

### Modos de conexão

| Modo | Inventário | Conexão | Escalonamento |
|---|---|---|---|
| `local` | `localhost,` | `-c local` | `-K` (senha do sudo) |
| `remote` | `<ip>,` | SSH, `-u <user>` | `-K` |
| `tunnel` | `<ip>,` | SSH via `ProxyCommand ssh -W` no bastion `<jump-user>@<jump-ip>` | `-K` |
| `sandbox` | nome do container | `-c docker -u dev` | sudo NOPASSWD dentro da imagem |

`remote` e `tunnel` validam o destino antes de executar qualquer comando. Não há default de `--ip` (só o `local` usa `localhost`). `--ip`, `--jump-ip`, `--jump-user` e `--user` passam pela função `require_value`: os espaços nas pontas são descartados (um espaço digitado no wizard continua valendo), e o resto só pode ter letras, números e `.`, `_`, `-`, sem começar com `-`. Uma vírgula ou um espaço virariam outro host no inventário `-i "<ip>,"`; aspas, `$`, `;` ou `%` quebrariam o `ProxyCommand`, que o ssh executa num shell local (ou seja, executariam comandos nesta máquina) ou virariam tokens do ssh; um `-` no início viraria opção do ssh. IPv6 e `host:porta` também ficam de fora, porque o `ssh -W %h:%p` e o `usuario@host` do `ProxyCommand` não os entendem; para eles, use um alias (`Host`, com `HostName` e `Port`) do `~/.ssh/config`. O `--user` aceita também `@` (logins como `jdoe@corp.example`, do SSSD/AD), porque só vira o `-u` do `ansible-playbook` e nunca entra no `ProxyCommand` (`LOGIN_RE`; os outros usam `NAME_RE`). O `tunnel` exige os três primeiros. Sem `--user`, o usuário SSH é o usuário atual (`whoami`); um `--user` vazio é recusado. As opções vêm só da linha de comando, não do ambiente.

`ansible.cfg` define `become = True` / `become_method = sudo` globalmente, e o callback de saída `ansible.builtin.default` com `callback_result_format = yaml`, mais o `ansible.posix.timer` (veja [Collections Ansible necessárias no controlador](#collections-ansible-necessárias-no-controlador)).

## Playbook `site.yml`

Um único play, `hosts: all`, `become: true`, `gather_facts: false`: os fatos são coletados nos `pre_tasks` (passos 4 e 7), primeiro só os da distro, sem sudo, depois todos, com sudo, como faria o `gather_facts`. Assim, as roles recebem os mesmos fatos de antes.

`pre_tasks`, todos com tag `always`, então rodam com qualquer `--tags`:

1. `assert` de que `ansible_version.full` é pelo menos `min_ansible_core_version` (`2.13`, em `vars:` do play), com `run_once`. Roda no controlador, então, abaixo do mínimo, o play para antes de qualquer contato com o host, com uma mensagem que mostra a versão encontrada e aponta para [Collections Ansible necessárias no controlador](#collections-ansible-necessárias-no-controlador). As collections não são verificadas: não há um teste nativo para isso no Ansible, e checar com o `ansible-galaxy` poderia consultar outro Ansible que não o que roda o play. O erro de uma collection ausente não a cita (por exemplo, `Could not find a matching action for the "xbps" package manager`), mas está na tabela de collections abaixo, que mostra a causa (#37). A senha do sudo (`-K`) é pedida antes, quando o `ansible-playbook` começa; no `sandbox`, a imagem é construída e o container recriado antes.
2. `include_vars {{ playbook_dir }}/../profiles/{{ profile }}.yml`: falha se o perfil não existir.
3. `include_vars {{ playbook_dir }}/../profiles/local.yml`, só quando o arquivo existe (`when: … is file or … is link`, avaliado no controller): overrides pessoais, fora do Git. Um `local.yml` que existe mas é inválido (YAML quebrado, conteúdo que não é dicionário, symlink quebrado) faz o play falhar logo no início.
4. `setup` com `gather_subset: ['!all']` e `become: false`: só os fatos mínimos (`distribution`, `os_family`…), sem sudo, para que a checagem seguinte apareça mesmo num host sem `sudo` (por exemplo, Alpine com `doas`). Precisa de `python3` no host: sem ele, o play falha aqui com `No python interpreter found`, antes da mensagem.
5. Um `block` que só roda quando `ansible_facts['os_family']` não está em `supported_os_families` (`Debian`, `Void`, `RedHat`, `Archlinux`, definida em `vars:` do play) e define o rótulo da distro uma vez. Numa distro fora da lista (Alpine, openSUSE, Gentoo…), um `fail` para o play aqui, antes de qualquer tarefa com sudo (a senha do `-K` ainda é pedida no início), com uma mensagem que mostra a distro detectada, as famílias suportadas e como forçar. Sem essa checagem, os `include_vars` das roles falhariam em silêncio e só os fallbacks mínimos seriam instalados. Para forçar a execução mesmo assim, defina `allow_unsupported_distro: true` (padrão `false`) no `profiles/local.yml`, o único caminho que também funciona pelo wizard, ou com `-e allow_unsupported_distro=true` (no `workstation.sh`, depois de `--`: `./workstation.sh local -- -e allow_unsupported_distro=true`); o `fail` é pulado e um `debug` com `⚠️` avisa que o resultado pode ficar parcial: as roles usam os fallbacks mínimos, e o Docker e o Go não têm ramo para a família, então não são instalados. A checagem fica depois dos perfis justamente para aceitar o override do `local.yml`. Ela é por família: derivados como Linux Mint, Pop!_OS ou Kali passam (`os_family: Debian`), mas o repositório do Docker ainda quebra neles (#22).
6. Só quando o alvo usa o dnf5 (Fedora ≥ 41, ou `pkg_mgr == 'dnf5'`): `assert` dos mínimos do ansible-core por ramo, `min_ansible_core_version_dnf5` (`2.15.11`) e `min_ansible_core_version_dnf5_2_16` (`2.16.6`), em `vars:` do play; qualquer 2.17+ passa. Fora deles, o Ansible não detecta o `dnf5` (2.14) ou o módulo falha (até o 2.15.10 e do 2.16.0 ao 2.16.5), e cada tarefa de pacote falharia depois, sem uma mensagem clara. Usa os fatos mínimos do passo 4, antes de qualquer tarefa com sudo. O `pkg_mgr` cobre os derivados do Fedora com outro nome de distro, mas só quando o ansible-core já detecta o dnf5: com o 2.14, um derivado passa pela checagem e falha depois.
7. `setup` completo, com sudo (o `become: true` do play).
8. Só quando `ansible_facts['pkg_mgr'] == 'dnf5'` (Fedora ≥ 41): garante o `python3-libdnf5`, de que o módulo `package` precisa no alvo. Tenta `import libdnf5` nos mesmos interpretadores que o módulo `dnf5` usa, primeiro o do Ansible (`ansible_facts['python']['executable']`), depois o `/usr/bin/python3`; o pacote conta como presente se algum deles importar (roda também em check mode, sem alterar nada). Ausente, o pacote é instalado com `dnf5 install -y python3-libdnf5`, com `LC_ALL=C`: se ele já estava instalado (o import falhou por outro motivo, como um pacote quebrado), o dnf5 responde `Nothing to do.` e a tarefa não conta como mudança, e o módulo de pacotes mostra o erro dele depois. Presente, nada roda (segunda execução sem `changed`). Uma falha da instalação (sem rede, proxy, repositório quebrado) só gera um aviso `⚠️` com a última linha de erro do dnf5 (ou o erro do Ansible, se o comando nem rodou), e as roles seguem com o padrão resiliente delas. Em check mode (`--dry-run`) e sem o pacote, para com uma mensagem que manda rodar uma vez sem `--dry-run` ou instalar o pacote, porque a simulação não altera o host e toda tarefa de pacote falharia. Como o `block` tem a tag `always`, isso vale para qualquer `--tags`, mesmo as que não instalam pacotes: quase todas as roles instalam, e repetir no `block` a lista de tags das roles criaria mais um lugar a manter. Fica antes das roles, para que nenhuma tarefa de pacote dependa da versão do controlador (veja a ressalva "Fedora ≥ 41" em [Collections Ansible necessárias no controlador](#collections-ansible-necessárias-no-controlador)).
9. `shell: echo $HOME && whoami` com `become: false`, registrado como `real_user_info`. Roda também em check mode.
10. `set_fact user_home` / `user_id`.

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
- O fallback `set_fact … when: X_packages is not defined` só entra quando não existe arquivo de vars para a distro (o `include_vars` tem `failed_when: false`). Como uma família fora de `supported_os_families` para o play nos `pre_tasks`, na prática ele só é alcançado com `allow_unsupported_distro: true`.
- Dicionários são **substituídos, não mesclados** (`hash_behaviour` padrão). Definir `devtools_features: {lazygit: false}` em `local.yml` remove a chave `tpm`, que então assume o `default()` da tarefa.
- Os defaults de features divergem: `devtools_features.*` e `ui_features.*` usam `default(false)`, e `languages_features.*` usa `default(true)`.

`os_family` usado nos nomes de arquivo: `Debian`, `Void`, `RedHat`, `Archlinux`. São as mesmas famílias de `supported_os_families` no `site.yml`. Uma família nova precisa entrar nos arquivos `vars/<os_family>.yml` das roles, em `supported_os_families` e nos mapas por família da role `languages` (`languages_go_package` e `languages_pipx_package`, em `vars/main.yml`); fora dos mapas, o Go e o pipx só geram aviso.

## Semântica de tags

Comportamento verificado com ansible-core 2.20:

- As tags declaradas em `roles:` no `site.yml` são herdadas por **todas** as tarefas da role, inclusive as carregadas por `include_tasks`.
- As tags num `include_tasks` se aplicam **só ao include**. As tarefas incluídas precisam repetir a tag para rodar quando aquela tag é selecionada.
- Uma tag que existe só dentro de um arquivo incluído não pode ser selecionada sozinha, porque o include não casa e o arquivo nem é carregado.
- `--list-tags` não mostra tags de tarefas incluídas dinamicamente.
- `ui` tem `never`, então só roda quando uma de suas tags é pedida explicitamente. `--tags all` (padrão) não inclui `ui`.

## Roles

### Padrão de instalação resiliente (devtools, editors, ui)

```
include_vars <os_family>.yml (failed_when: false)
set_fact <role>_packages (fallback mínimo, se indefinido; só com allow_unsupported_distro)
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
  2. lê a versão instalada com `/usr/local/bin/lazygit --version` (o `version=` da saída) e consulta `api.github.com/…/releases/latest`, ambos com `check_mode: false`;
  3. só quando não há binário em `/usr/local/bin/lazygit` ou a versão instalada é mais antiga que a última release, um único `unarchive` baixa o asset e extrai só o binário em `/usr/local/bin` (`include: [lazygit]`, `0755`, `root`). Uma versão mais nova que a release não é rebaixada, e um binário cuja versão não é reconhecida (ex.: `version=unversioned` de um build local) não é tocado, só gera aviso. Se a tag da última release não parece uma versão (ex.: `nightly`), nada é instalado e há um aviso. Um symlink em `/usr/local/bin/lazygit` é trocado por um arquivo regular, e a extração não é atômica: se for interrompida, o binário fica truncado até a execução seguinte, que o reinstala. Em check mode, não baixa: uma tarefa `debug` com `changed_when: true` informa a versão que seria instalada;
  4. no `rescue`, só falha de rede ou rate limit vira aviso e o play continua. A classificação é pelo resultado, não pelo nome da tarefa: `status` -1, 403, 429 ou 5xx no `uri`, ou `Request failed`/`urlopen error`/`timed out`/`HTTP Error 5xx` na mensagem. Um 404 no asset (asset renomeado, arquitetura deixou de ser publicada) e erros ao extrair, gravar ou montar templates falham o play, com `rc` e `stderr` quando existem. Não há fallback para pacote da distro. Só `/usr/local/bin/lazygit` é consultado: um Lazygit em outro caminho (pacote da distro, `~/go/bin`) é ignorado e ganha uma segunda cópia.

  A API do GitHub ainda é consultada a cada execução (60 requisições por hora sem token), porque a versão desejada é sempre a última; fixar a versão é a #26.
- TPM: `git clone` em `~/.tmux/plugins/tpm` quando `devtools_features.tpm`.

### languages
`main.yml` só tem `include_tasks`, um por linguagem, cada um com sua tag.

| Arquivo | Mecanismo |
|---|---|
| `python.yml` | uv via `curl https://astral.sh/uv/install.sh \| sh` (`UV_INSTALL_DIR=~/.local/bin`, `creates:`), pipx pelo pacote do sistema, mapeado em `languages_pipx_package` (`vars/main.yml`): `pipx` em Debian e RedHat, `python-pipx` no Arch, `python3-pipx` no Void (uma família fora do mapa só gera aviso), e `python3 -m pipx ensurepath`, só com o pipx instalado. A instalação fica num `block`/`rescue`: uma falha (sem EPEL no RHEL, sem o universe no Ubuntu, sem rede) só gera um aviso `⚠️` com a última linha do erro real, e o play segue. O `ensurepath` continua com `failed_when: false`, então uma falha dele não gera aviso (a #18 trata do `ensurepath`). Como o mapa vem de `vars/` da role, um perfil carregado por `include_vars` que define `languages_pipx_package` o substitui inteiro (sem merge), e as famílias que ficarem de fora só geram aviso. O pipx só é instalado aqui, condicionado por `languages_features.python`; as listas da `devtools` não o trazem, então `--tags devtools` ou `python: false` não instalam o pipx |
| `node.yml` | pacote `nodejs`, só se o `node` ainda não funcionar (`node --version`): um Node.js de outro pacote (por exemplo, `nodejs-lts-*` no Arch, que conflita com o `nodejs`) é mantido, com uma mensagem `ℹ️` que mostra a versão; vale para as quatro famílias. Depois, o pacote `npm`, só se o `npm` ainda não funcionar (`npm --version`). O npm é um pacote separado no Debian/Ubuntu e no Arch, mas vem com o `nodejs` no Void e no Fedora, e o `nodejs` do NodeSource o traz e declara conflito com o pacote `npm` da distro (o apt recusaria a instalação). A instalação do `npm` fica num `block`/`rescue`: uma falha (indisponível, conflito, sem rede) só gera um aviso `⚠️` com a última linha do erro real (o stderr no apt, no pacman e no xbps, `failures` no dnf, o `module_stderr` se o módulo quebrou, e por último o `msg`), e o play segue. As duas checagens rodam como root, com o PATH que o sudo der: onde o sudoers fixa o `secure_path` (Debian/Ubuntu, Fedora), um node ou npm só do PATH do usuário (nvm, volta) não é visto e os pacotes da distro são instalados também; onde não fixa (Arch, Void), o PATH do usuário passa, e um node do nvm que funciona faz a instalação ser pulada. No fim, uma conferência com `node --version` avisa `⚠️` se o node do PATH não funcionar (por exemplo, um shim quebrado antes do pacote no PATH). Um `node` que não veio de pacote e não traz npm (por exemplo, um tarball em `/usr/local/bin`) não impede o pacote `npm` da distro, que puxa o `nodejs` como dependência, e o host fica com dois Node.js. No `--dry-run` do Void e do Fedora, a instalação do `npm` aparece como mudança, porque o `nodejs` (que já o traria) ainda não foi instalado. No Debian/Ubuntu, o pacote `npm` puxa centenas de pacotes `node-*` e, pelos Recommends, o toolchain de compilação: é o empacotamento da distro, e o `package` não desliga os Recommends |
| `rust.yml` | `stat` em `~/.cargo/bin/rustup`, depois o instalador oficial `sh.rustup.rs -y --no-modify-path` (`failed_when: false`), com fallback para o pacote `cargo` se o instalador falhar |
| `go.yml` | um pacote por `os_family`, mapeado em `languages_go_package` (`vars/main.yml`): `golang` em Debian e RedHat, `go` em Void e Arch. Uma família fora do mapa só gera um aviso (`⚠️`) e o play segue. Como a variável vem de `vars/` da role, um perfil carregado por `include_vars` a sobrescreve (mapa inteiro, sem merge) |

### docker
- `debian.yml`: chave GPG em `/etc/apt/keyrings/docker.asc`, repositório `download.docker.com/linux/<distribution>` com arch mapeada por `docker_apt_arch` (`vars/main.yml`), pacotes `docker-ce`, `docker-ce-cli`, `containerd.io` e plugins buildx e compose. A URL do repositório fica em `_docker_apt_repo_url` (`set_fact` no início). Em check mode, quando o repositório mudaria (ainda não configurado), pula a instalação e informa que o Docker seria instalado, porque o índice do apt não teria o `docker-ce`; com o repositório já configurado, o check da instalação roda normalmente. Diferente do `redhat.yml`, não olha o `/usr/bin/dockerd`, que o `docker.io` da distro também traz. O check mode no Debian/Ubuntu também precisa do `python3-apt` no alvo (#52).
- `redhat.yml` (`os_family == RedHat`): repositório oficial `download.docker.com/linux/<dir>`, com `<dir>` mapeado da `distribution` por `docker_rpm_repo_distro` (`vars/main.yml`): `Fedora` → `fedora`, `RedHat` → `rhel`, `CentOS`/`Rocky`/`AlmaLinux` → `centos`. Outra distro da família só recebe um aviso, e nada é instalado. Importa a chave com `rpm_key` e grava o repositório com `yum_repository` (`$releasever/$basearch/stable`), sem depender do `dnf config-manager`, cuja sintaxe muda no dnf5. O repositório fica na seção `docker-ce-stable` de `/etc/yum.repos.d/docker-ce.repo`, os mesmos do arquivo oficial, para não duplicar o repositório num host que seguiu o guia do Docker, e com `skip_if_unavailable`: numa versão do Fedora que o Docker ainda não publicou, o `$releasever` dá 404, a instalação do Docker falha e o play para nesta role, mas o repositório que fica gravado não quebra o dnf das outras roles nas execuções seguintes, por exemplo com outras `TAGS` (sem o `skip_if_unavailable`, toda operação do dnf5 falha com `Usable URL not found`). Instala os mesmos pacotes do Debian (`docker-ce`, `docker-ce-cli`, `containerd.io` e os plugins buildx e compose). Em check mode, quando o repositório mudaria (ainda não configurado, ou diferente) e o Docker não está instalado (sem `/usr/bin/dockerd`), pula a instalação e informa que o Docker seria instalado; com ele instalado, o check da instalação roda normalmente. Não trata o conflito com `moby-engine`, `podman-docker` e `runc`: com um deles instalado, o play para na role (#60). Só o Fedora (44) é validado no sandbox, e também num container com systemd como PID 1; RHEL, CentOS, Rocky e Alma não têm imagem.
- `archlinux.yml` (`os_family == Archlinux`): pacotes `docker`, `docker-buildx` e `docker-compose` do repositório `extra`.
- `void.yml`: pacote `docker` (com `update_cache: true`) e, depois, `docker-buildx` e `docker-compose`, cada um numa transação própria (`void_plugin.yml`, num `include_tasks` com loop, sem sincronizar o índice de novo). Os plugins ficam em `/usr/libexec/docker/cli-plugins/` e são pacotes separados, com versões próprias; um plugin indisponível só gera um aviso `⚠️` com a última linha do erro, sem impedir o Docker nem o outro plugin. Cria o symlink `/etc/sv/docker` → `/var/service/docker` só se os dois caminhos existirem. No Void, o Ansible reporta `service_mgr = service`, não `runit`.
- Serviço (em `main.yml`, um passo só para Debian, RedHat e Arch): com `service_mgr == systemd`, coleta os serviços (`service_facts`) e habilita e inicia o `docker` só se o `docker.service` existir. Ele vem do pacote: numa distro sem instalação, ou em check mode antes dela, não existe, e o módulo `service` falharia.
- Para todas as distros: consulta o grupo `docker` com `getent` e adiciona `user_id` a ele se existir. Se não existir em check mode ou numa distro sem tarefa de instalação (`docker_install_supported`, `vars/main.yml`), só avisa, em vez de falhar no módulo `user`; depois de uma instalação real, a falta do grupo falha o play com uma mensagem clara, para o usuário não ficar sem acesso ao Docker com o play terminando ok.

### zsh
Pacotes `zsh` e `git`, shell padrão `/bin/zsh` para `user_id`, e `git clone` (branch `master`) de Oh-My-Zsh, Powerlevel10k e dos plugins `zsh-autosuggestions`, `zsh-syntax-highlighting` e `zsh-completions`. Não gera `.zshrc`; isso fica a cargo dos dotfiles.

### ui (opt-in)
Pacotes Sway/Wayland por distro. Se `ui_features.fonts` estiver ativo, baixa a JetBrainsMono Nerd Font (release fixo `v3.0.2`) para `~/.local/share/fonts` e, logo em seguida, roda `fc-cache` só nessa pasta, apenas quando o download rodou (`ui_nerdfont_download` definido e não pulado). É uma task, e não um handler, para rodar logo depois do download sem precisar de `meta: flush_handlers`, que vale para o play inteiro. A condição é `is not skipped`, e não `is changed`, porque `is changed` dispara a regra `no-handler` do ansible-lint. Por isso o `fc-cache` roda sempre que o download roda, mesmo se o `unarchive` não mudou nada (por exemplo, com o zip já parcialmente extraído), o que só custa uma reconstrução de cache a mais.

### editors
Neovim, ferramentas de clipboard (`xclip`, `wl-clipboard`) e `lldb`, nas quatro famílias.

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
| `api.github.com` + releases `jesseduffield/lazygit` | devtools | latest (baixa só quando não há binário ou o instalado é mais antigo) |
| `github.com/tmux-plugins/tpm` | devtools | `master` |
| `github.com/ohmyzsh/ohmyzsh`, `romkatv/powerlevel10k`, `zsh-users/*` | zsh | `master` |
| `download.docker.com` | docker (Debian, RedHat/Fedora) | canal `stable` |
| `github.com/ryanoasis/nerd-fonts` | ui | `v3.0.2` |
| `github.com/jozielsc/dotfiles` | dotfiles | `main` |

Todas exigem acesso à internet a partir do host provisionado.

### Collections Ansible necessárias no controlador

Esta seção é a fonte única dos requisitos do controlador. README e USAGE apenas apontam para cá.

**ansible-core ≥ 2.13.** O mínimo vem do `callback_result_format` (`ansible.cfg`), que surgiu no 2.13. Em versões anteriores, a opção seria ignorada sem aviso e a saída voltaria a ser JSON; por isso o play verifica o mínimo logo no início e para abaixo dele (passo 1 dos `pre_tasks` em [Playbook `site.yml`](#playbook-siteyml), #37). O provisionamento completo foi validado no ansible-core 2.20 (sistema) e 2.21 (ambiente do uv), e o 2.18 contra o Fedora 44 (#56); do 2.13 só se verificou que o play passa da checagem e roda os `pre_tasks`.

**Pacote completo `ansible`.** Não há `requirements.yml` (#20). As collections abaixo vêm no pacote `ansible`, mas **não** numa instalação só de `ansible-core` (pip ou pacote `ansible-core` da distro). Nesse caso, instale-as com `ansible-galaxy collection install <nome>`.

Ressalvas por distro do controlador:
- **Ubuntu 22.04 e Debian 11:** o `apt install ansible` instala o Ansible 2.10, abaixo do mínimo: o playbook roda, mas a saída sai em JSON. Use uma versão mais nova (PPA `ppa:ansible/ansible`, `pipx install ansible` ou o ambiente do uv).
- **RHEL 8/9:** o AppStream só tem `ansible-core`. O pacote `ansible` exige o EPEL; sem ele, instale as collections com `ansible-galaxy`.

Ressalva por distro do alvo:
- **Fedora ≥ 41 (dnf5):** precisa no controlador de um ansible-core 2.15.11+, 2.16.6+ ou 2.17+, e do `python3-libdnf5` no alvo. Testado contra o Fedora 44 (2026-10-15): o 2.14.18 detecta o gerenciador como `dnf` e pede o `python3-dnf`; do 2.15.0 ao 2.15.10 e do 2.16.0 ao 2.16.5, o `dnf5` é detectado, mas o módulo falha (`MODULE FAILURE` ou `'Base' object has no attribute 'load_config_from_file'`); o 2.15.11 em diante, o 2.16.6 em diante e o 2.17+ instalam. O play exige esses mínimos por ramo para esses alvos e para antes, com uma mensagem clara (passo 6 dos `pre_tasks`). O `python3-libdnf5` é garantido pelo play antes das roles (passo 8 dos `pre_tasks` em [Playbook `site.yml`](#playbook-siteyml)). Sem isso, o módulo `dnf5` do ansible-core ≥ 2.19 o instalaria sozinho na primeira tarefa de pacote (`auto_install_module_deps`, padrão `true`), mas não em check mode (`python3-libdnf5 must be installed to use check mode`), e o 2.18 e anteriores falham (`Could not import the libdnf5 python module`), verificado em 2026-10-15 com o 2.21 e o 2.18 contra o Fedora 44. A imagem do sandbox `fedora` não traz o pacote, então o sandbox exercita essa instalação.

| Collection | Usada por | Sem ela |
|---|---|---|
| `community.general` | módulo `package` no Void (`xbps`) e no Arch (`pacman`) | **bloqueante**: a instalação de pacotes falha nessas distros (`Could not find a matching action for the "xbps" package manager`) |
| `community.docker` | conexão `-c docker` do `scripts/workstation.sh sandbox` | o sandbox não conecta ao container |
| `ansible.posix` | callback `ansible.posix.timer` (`ansible.cfg`) | opcional: o Ansible só avisa e não mostra o tempo total |

O callback de saída (`ansible.builtin.default`) não depende de collection.

## Matriz de suporte por plataforma

Estado do código na v2.0.0 (2026-10). Atualize esta tabela quando a cobertura mudar. Uma distro de outra família para o play no início (passo 5 dos `pre_tasks` em [Playbook `site.yml`](#playbook-siteyml)), a menos que `allow_unsupported_distro` seja `true`.

| Componente | Debian/Ubuntu | Void | RedHat/Fedora | Arch |
|---|---|---|---|---|
| devtools | ✅ | ✅ | ✅ | ✅ |
| python / node / rust | ✅ | ✅ | ✅ | ✅ |
| go | ✅ | ✅ | ✅ | ✅ |
| docker | ✅ repo oficial | ✅ pacotes + runit | ✅ repo oficial (Fedora, RHEL, CentOS/Rocky/Alma) | ✅ pacotes `extra` |
| zsh / editors / dotfiles | ✅ | ✅ | ✅ | ✅ |
| ui | ✅ | ✅ | ✅ | ✅ |
| Sandbox Docker | `ubuntu` (24.04) | `void` (glibc) | `fedora` (44; não cobre RHEL/Rocky nem EPEL) | `arch` (rolling) |

## Testes

- O CI (`.github/workflows/ci.yml`, GitHub Actions) roda em todo PR e em push na `main`: `uv sync --locked` e `uv run --locked just lint`, ou seja, as mesmas checagens e versões (`uv.lock`) do ambiente local. A versão do próprio uv no CI é fixa no workflow (`version:` do setup-uv) e deve acompanhar a usada localmente. Ele só faz análise estática; o provisionamento continua validado manualmente pelo sandbox (`scripts/workstation.sh sandbox`), cujo CI é a #29. As actions são pinadas por SHA, com a tag num comentário. Em PR, um push novo cancela o run anterior; na `main`, o grupo de concorrência é por commit, para que todo commit mergeado tenha resultado.
- Ferramentas de desenvolvimento vêm do grupo `dev` do uv (`pyproject.toml`, `uv.lock`; `uv sync`). O projeto não é um pacote Python (`[tool.uv] package = false`). O grupo inclui o `rust-just`, o pacote do PyPI com o binário oficial do [just](https://github.com/casey/just), então as receitas do `justfile` rodam com `uv run just <receita>` (ou `just <receita>` com o `.venv` ativado), a partir de qualquer pasta do repositório: o just roda as receitas na pasta do `justfile`, exceto o `sandbox` (`[no-cd]`), que roda na pasta de quem chama, como o script, para que caminhos relativos nos argumentos extras (`-e @vars.yml`) valham a partir dela. `uv run just` sozinho lista as receitas. As receitas usam `bash -euo pipefail`, então a primeira falha interrompe a receita. `just lint` roda, em sequência e parando na primeira falha, `ansible-playbook playbooks/site.yml --syntax-check`, `ansible-lint`, `yamllint --strict .` e `shellcheck` em todo `*.sh` versionado (`git ls-files`), todos via `uv run --locked` (o `shellcheck` vem do pacote `shellcheck-py`, então não depende do pacote da distro; o `uv.lock` só tem wheel para Linux x86_64 glibc, macOS e Windows, e em ARM ou musl, como o Void musl, o `uv sync` compila o sdist, que baixa o binário do shellcheck durante o build e falha sem rede; o `shellcheck` roda sobre o `git ls-files '*.sh'`, então o `just lint` precisa de um clone git); `just test` roda `uv run --locked molecule test`; `just check` tem `lint` e `test` como dependências, que o just roda em ordem, uma por vez (o test só roda se o lint passar); `just sandbox [distro] [tags] [args…]` só chama o `./scripts/workstation.sh sandbox --distro … --tags …`, com os argumentos extras depois de `--` (um `--` digitado logo depois das tags não é repetido; qualquer outro vai como está para o `ansible-playbook`). Distro e tags vão na forma `--opção valor`, em que o script recusa um valor que começa com `-`: `just sandbox ubuntu -vv`, sem as tags, sai com erro em vez de rodar só as tarefas `always`. Os parâmetros chegam ao script como argumentos posicionais, sem interpolação do just no shell. Com `uv run`, o `ansible-playbook` do sandbox é o do `.venv`, não o do sistema. O `--locked` faz cada ferramenta rodar com as versões do `uv.lock` e falhar se ele estiver desatualizado. Mas o `uv run just …` de fora, sem `--locked`, atualiza o `uv.lock` (e o `.venv`) antes de chamar o just quando o `pyproject.toml` mudou: o lock novo aparece no `git status` e precisa entrar no commit, e o CI, que roda `uv run --locked just lint`, falha se ele ficar de fora. O cenário Molecule ainda não existe (#34) e, quando existir, é **adicional** ao sandbox. Os comandos de provisionamento do `scripts/workstation.sh` (`local`, `remote`, `tunnel`, `sandbox`) usam o `ansible-playbook` do `PATH`: chamados direto, o do sistema, e lint e testes rodam com outro ansible-core e outras collections (#38); chamados via `uv run` (como em `uv run just sandbox`), o do `.venv`.
- As imagens do sandbox criam o usuário `dev` com sudo NOPASSWD e mantêm o container vivo com `tail -f /dev/null`. Não há init, então caminhos de serviço (systemd e runit) não são exercitados.
- Imagens: `ubuntu:24.04`, `void-glibc-full:latest`, `fedora:44` e `archlinux:base`. O Void e o Arch são rolling, mas o `scripts/workstation.sh sandbox` roda `docker build` sem `--pull` nem `--no-cache`, então a imagem fica no cache de camadas do Docker e continua com os pacotes e o índice do primeiro build. Para testar o estado atual da distro, remova a imagem (`docker rmi workstation-sandbox-image-<distro>`) ou rode `docker build --pull --no-cache` antes; um índice velho faz a instalação em lote falhar (#55). No Fedora, a imagem não traz o `python3-libdnf5` (veja a ressalva "Fedora ≥ 41" em [Collections Ansible necessárias no controlador](#collections-ansible-necessárias-no-controlador)). O `fedora` não cobre RHEL/Rocky, que precisam do EPEL para parte de `vars/RedHat.yml`. No Arch, a imagem roda `pacman -Syu` junto com a instalação, porque o Arch não suporta atualização parcial.
- Para adicionar uma distro ao sandbox, crie `tests/sandbox/Dockerfile.<nome>` com `python3`, `sudo` e o usuário `dev`. O `scripts/workstation.sh` detecta o arquivo pelo nome; `sandbox`, `sandbox-shell` e `sandbox-clean` recusam uma distro sem Dockerfile. As distros também são listadas na tela `distro` do wizard (`scripts/interactive.sh`), no `help` do `scripts/workstation.sh`, no `README.md` (PT e EN, incluindo a árvore de `tests/sandbox/`), no `docs/USAGE.md` (`sandbox`, `--distro`), na matriz de suporte acima, no `CLAUDE.md` e na definição de pronto do `docs/WORKFLOW.md`; atualize todos.
- Verificações estáticas disponíveis: `ansible-playbook … --syntax-check`, `--list-tasks`, `--list-tags` e o `--print` do `scripts/workstation.sh`, que mostra os comandos sem executá-los. `just lint` passa sem falhas. Configs versionadas: `.ansible-lint` (perfil `production`, sem `skip_list`/`warn_list`; o ansible-lint já ignora o que está no `.gitignore`), `.yamllint` (o default do yamllint com os ajustes que o ansible-lint exige para considerá-la compatível; o ansible-lint usa o mesmo arquivo na regra `yaml`) e `.shellcheckrc` (sem exceções). O `.yamllint` ignora `.venv/`, `.ansible/` e `profiles/local.y*ml` por uma lista explícita. O `**/` dos padrões de `profiles/` cobre a raiz e os caminhos absolutos que um editor passa, mas não um caminho relativo dentro de `profiles/`. A regra `truthy` também verifica chaves, por isso o `"on":` dos workflows fica entre aspas. O `shellcheck` recebe a lista do `git ls-files`, ou seja, do índice do git: um script novo sem `git add` só é checado no CI, e fora de um clone git o `just lint` falha logo no início. Uma exceção nova entra na config comentada e com a Issue que trata dela. Variáveis criadas por `register`/`set_fact` dentro de uma role levam o prefixo da role (`devtools_lazygit_release`; `_devtools_lazygit_arch` para fatos internos), como exige a regra `var-naming[no-role-prefix]`.

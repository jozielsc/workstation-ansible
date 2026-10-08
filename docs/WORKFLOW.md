# Fluxo de Trabalho

Regras para qualquer pessoa ou agente que analise, modifique ou evolua este projeto. O fluxo com o GitHub foi adaptado do projeto `jozielsc/refactored-dash`.

## Princípios

- **O backlog único é o GitHub Project "workstation-ansible"** (#6 de `jozielsc`, https://github.com/users/jozielsc/projects/6). Ele é alimentado pelas Issues de `jozielsc/workstation-ansible`. Trabalho identificado vira Issue no board, não fica só em documento, comentário ou conversa.
- **O conhecimento do projeto fica em `docs/`.** O `CLAUDE.md` contém só o essencial e estável e aponta para `docs/`.
- **Analisar não autoriza alterar código.** Durante uma análise, só é permitido documentar e criar ou atualizar Issues. Código de produção (playbooks, roles, Makefile, scripts, perfis) só muda quando a implementação é pedida explicitamente.
- **Divergência com o legado.** Quando o estado atual do repositório diverge de uma regra deste documento, código novo ou alterado segue a regra. Não saia corrigindo todo o legado sem uma Issue para isso.

## Código ↔ documentação ↔ Issues

Cada fonte tem um papel, e as três precisam estar **sempre consistentes**:

| Fonte | Representa | Responde |
|---|---|---|
| Código | A implementação atual | — |
| `docs/` | O conhecimento atual do projeto | O que o sistema é, como funciona e por que foi desenhado assim |
| Issues (Project #6) | O trabalho acionável que falta | O que precisa ser feito |

- **Não duplique informação.** Uma Issue que precisa de contexto técnico **referencia** a seção do `docs/`, em vez de copiá-la. Na Issue fica só o que é específico do trabalho: o comportamento atual a mudar, o resultado desejado, os critérios de aceite.
- **Mudou o comportamento ou a arquitetura, atualize a documentação no mesmo trabalho** (mesmo PR). Nunca deixe a documentação descrevendo um comportamento obsoleto depois de concluir uma mudança.
- **Trabalho substancial só está concluído quando o conhecimento resultante está documentado.**
- Quando o código, a documentação e as Issues divergem, corrija a divergência: ajuste o doc, comente ou edite a Issue, ou abra uma Issue para o código.

## Documentação

Registre em `docs/` toda descoberta relevante: comportamento do sistema, arquitetura, relações de dependência, restrições técnicas, comportamento legado e decisões de design.

| Arquivo | Conteúdo |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Como o sistema funciona: fluxo, precedência de variáveis, tags, roles, integrações, matriz de plataformas |
| [TECH_DEBT.md](TECH_DEBT.md) | Comportamentos problemáticos e limitações **atuais** (o que o sistema faz hoje), cada item com o nível de evidência e o link para a Issue que trata dele. O "o que fazer" fica só na Issue |
| [USAGE.md](USAGE.md) | Manual do usuário final |
| `WORKFLOW.md` | Este documento |

- Prefira atualizar um documento existente a criar um novo e redundante.
- Análises extensas vão para `docs/`, nunca para o `CLAUDE.md`.
- A documentação afetada por uma mudança é atualizada **no mesmo PR**, nunca depois. Ao corrigir um item do `TECH_DEBT.md`, remova-o ou marque como resolvido, citando o PR.

## Issues

### Quando criar

Crie uma Issue para trabalho **concreto e acionável**, por exemplo:

- bug
- dívida técnica
- refatoração
- melhoria arquitetural
- teste ausente
- questão de segurança
- problema de performance
- atualização de dependência
- lacuna de documentação
- feature futura
- migração

Não crie Issue:
- só porque algo é incomum, ou porque uma alternativa seria teoricamente melhor;
- para melhorias especulativas sem evidência no projeto. Itens "A verificar" do `TECH_DEBT.md` só viram Issue quando houver evidência suficiente, ou como uma Issue explícita de investigação com critério de aceite claro;
- duplicada.

### Antes de criar: evitar duplicatas

```bash
gh issue list --state all --search "<palavras-chave>" --limit 50
gh issue list --state closed --search "<palavras-chave> closed:>$(date -d '-90 days' +%F)"
```

Se uma Issue aberta ou fechada recentemente já cobre o mesmo trabalho, **comente nela ou atualize-a** (`gh issue comment` ou `gh issue edit`) em vez de criar outra.

### Conteúdo obrigatório

Toda Issue criada a partir de uma análise deve ter:

```markdown
## Problema / motivação
## Comportamento atual
## Resultado desejado
## Contexto técnico
## Arquivos / módulos relevantes
## Dependências / bloqueios
## Critérios de aceite
- [ ] ...
## Referências
- docs/<arquivo>.md#<seção> (ex.: docs/TECH_DEBT.md, item B3)
```

- Em "Contexto técnico", aponte para a seção do `docs/` que explica o funcionamento, e escreva só o que é específico da Issue (abordagens possíveis, restrições do trabalho). Não copie a explicação.
- O título deve ser claro e específico, sem `Closes`/`Fixes`. Escreva o conteúdo em português.
- Use apenas labels que já existem (`gh label list`): `bug`, `enhancement`, `documentation`, `good first issue`, `help wanted`, `question`. Crie labels novas só se pedirem.
- Issues relacionadas são ligadas pelos relacionamentos do GitHub: sub-issue para dividir um épico, "blocked by"/"blocks" para dependência real. Na falta disso, cite `#<n>` no corpo.
- **Toda Issue nova entra no board** com `Status = Backlog` e com `Priority` e `Size` preenchidos (`Estimate` quando der para estimar). Veja os comandos em [Operando o board via CLI](#operando-o-board-via-cli).

### Rastreabilidade

- A documentação aponta para a Issue: no `TECH_DEBT.md`, cada item rastreado leva o link `#<n>`.
- A Issue aponta para a documentação, na seção "Referências".
- O corpo do PR traz `Closes #<n>`, e os commits trazem `Refs #<n>`.

## Board (GitHub Project #6)

- **`Status`** é a coluna do card: `Backlog → Ready → In progress → In review → Done`.
- **`Priority`** (P0/P1/P2), **`Size`** (XS/S/M/L/XL) e **`Estimate`** (pontos) são **campos** do item, não status.
- Um card só passa para `Ready` quando está refinado o bastante para começar sem perguntas em aberto.
- **Board sempre limpo:** sem cards órfãos, duplicados ou na coluna errada. Valide o estado do board ao fim de cada sequência de trabalho.
- As automações do Project ("Item closed", "Pull request merged", "Pull request linked to issue", "Auto-close issue") podem mover cards sozinhas. Depois de qualquer vínculo, merge ou fechamento, **confira o status do card e corrija** o que for preciso.

### Operando o board via CLI

IDs do Project #6 (estáveis enquanto os campos não forem recriados):

| Campo | Field ID | Opções |
|---|---|---|
| Project | `PVT_kwHOAEICSc4BmILk` | — |
| Status | `PVTSSF_lAHOAEICSc4BmILkzhkyaTk` | Backlog `f75ad846` · Ready `61e4505c` · In progress `47fc9ee4` · In review `df73e18b` · Done `98236657` |
| Priority | `PVTSSF_lAHOAEICSc4BmILkzhkyaZ4` | P0 `79628723` · P1 `0a877460` · P2 `da944a9c` |
| Size | `PVTSSF_lAHOAEICSc4BmILkzhkyaZ8` | XS `6c6483d2` · S `f784b110` · M `7515a9f1` · L `817d0097` · XL `db339eb2` |
| Estimate | `PVTF_lAHOAEICSc4BmILkzhkyaaA` | número |

```bash
# adicionar a Issue ao board (devolve o item id)
ITEM=$(gh project item-add 6 --owner jozielsc --url <issue-url> --format json --jq .id)

# definir campos (um campo por chamada)
P=PVT_kwHOAEICSc4BmILk
gh project item-edit --project-id $P --id $ITEM --field-id PVTSSF_lAHOAEICSc4BmILkzhkyaTk --single-select-option-id f75ad846   # Status=Backlog
gh project item-edit --project-id $P --id $ITEM --field-id PVTSSF_lAHOAEICSc4BmILkzhkyaZ4 --single-select-option-id da944a9c   # Priority=P2
gh project item-edit --project-id $P --id $ITEM --field-id PVTSSF_lAHOAEICSc4BmILkzhkyaZ8 --single-select-option-id f784b110   # Size=S
gh project item-edit --project-id $P --id $ITEM --field-id PVTF_lAHOAEICSc4BmILkzhkyaaA --number 3                              # Estimate

# inspecionar o board
gh project item-list 6 --owner jozielsc --format json
```

Se algum ID mudar, consulte de novo com `gh project field-list 6 --owner jozielsc --format json`. O `gh` precisa do escopo `project`.

## Fluxo de uma Issue (feature ou bugfix)

Não pule etapas e não abra branch sem uma Issue por trás.

1. **Planejamento (Backlog).** Toda história vira uma Issue no board como `Backlog`, com `Priority` e `Size`.
2. **Descoberta.** Numa sessão focada em backlog, liste os cards `Ready` por prioridade, ou siga a Issue que o usuário indicar.
3. **Planejamento técnico (ainda em Ready).** Leia a Issue e a documentação relevante e **verifique se as duas ainda refletem o estado atual do código**. Se alguma estiver desatualizada, corrija antes de seguir: ajuste o doc, ou registre na Issue o que mudou (ou feche a Issue, se o trabalho já não fizer sentido). Explore o código e desenhe a solução. Depois anexe `## Plano de implementação` ao **corpo da Issue** (`gh issue edit <n> --body-file <arquivo>`), preservando a descrição original. Se preciso, divida a Issue em sub-issues.
4. **Uma branch por Issue, derivada da `main` atualizada**, com o número da Issue no final:
   ```bash
   git fetch origin main
   git switch -c <type>-<slug>-<N> origin/main   # ex.: fix-remote-ip-default-12
   ```
   - O formato é `<type>-<slug>-<N>`: hífens, sem `/`, e `<type>` é um tipo do Conventional Commits. No refactored-dash, foi com esse formato que o vínculo automático entre PR e Issue passou a funcionar.
   - Não use `gh issue develop`.
   - Nunca crie branch sem Issue, nunca derive de outra branch e nunca reaproveite a branch de outra Issue. Se a Issue depender de código que ainda não está na `main`, avise e confirme com o usuário como proceder.
5. **Mova o card para `In progress`** só quando a implementação começar de fato, não durante a exploração.
6. **Implemente seguindo a [Definição de pronto](#definição-de-pronto):** rode os testes adequados e atualize a documentação no mesmo PR sempre que o conhecimento do sistema mudar.
7. **Registre decisões como comentários na Issue** (trade-offs, achados fora do escopo). O corpo da Issue guarda o plano e os comentários são o diário de bordo. Não misture os dois.
8. **Commit, push e PR.**
   - O PR vai sempre para a `main` (`--base main`).
   - O **corpo** do PR traz `Closes #N` (ou `Fixes #N`). **Nunca** coloque essa palavra-chave no título.
   - Depois de abrir o PR, confira a base e o vínculo:
     ```bash
     gh pr view <PR> --json baseRefName,closingIssuesReferences
     ```
     Se `closingIssuesReferences` vier vazio, avise o usuário antes de seguir. Ele faz o vínculo manual pelo painel **"Development"** do PR, que não tem API.
   - **Quando houver CI**, aguarde o resultado depois de cada push (`gh pr checks <PR> --watch`). Se ficar vermelho, leia `gh run view <id> --log-failed`, **reporte ao usuário e pergunte** se deve corrigir.
   - Mova o card para `In review` quando o PR estiver aberto (e com o CI verde, quando houver CI).
   - A Issue só fecha com o merge do PR na `main`. Nunca feche antes.
9. **Code review em rodadas, até tudo estar ok.** Com o card em `In review`:
   1. Rode `/code-review <PR> --comment`, para que os achados fiquem registrados como comentários no PR, na linha, e não só no chat.
   2. Leia o PR e os achados e procure bloqueantes e problemas.
   3. **Se houver apontamentos:** reporte ao usuário e **pergunte se deve aplicar as correções**. Se ele disser sim:
      - mova o card para `In progress` e corrija no mesmo PR;
      - rode as verificações da Definição de pronto de novo e faça commit e push;
      - volte o card para `In review` e faça uma **nova rodada** (passo 9.1).
   4. **Sem apontamentos:** registre no PR que a rodada saiu limpa e aguarde o pedido de merge.

   **Achados relevantes não corrigidos sempre viram uma Issue nova** no board, com `Priority` e `Size`. Nunca ficam só num comentário de PR. Achados da mesma rodada podem ser agrupados numa única Issue.
10. **Merge só com pedido explícito do usuário.** Nunca faça merge por iniciativa própria, e nunca com o CI vermelho. Depois do merge:
    - mova o card para `Done`;
    - confirme que a Issue foi fechada. Se o `Closes #N` não a fechou, feche manualmente com um comentário citando o PR e o merge commit;
    - apague a branch local e a remota (o repositório não tem "delete branch on merge" ativo);
    - atualize a `main` local (`git switch main && git pull --ff-only`).
11. **Board limpo** ao fim da sequência de trabalho.

## Definição de pronto

- `ansible-playbook playbooks/site.yml --syntax-check -i localhost,` passa.
- `make lint` (`uv run ansible-lint`) sem erros nos arquivos tocados.
- `make test` (`uv run molecule test`) passa, quando o cenário Molecule existir (#34). Ele complementa o sandbox, não o substitui.
- As tags afetadas foram executadas no sandbox, em `void` e `ubuntu` (`make sandbox DISTRO=<d> TAGS=<tags>`), sem falhas. Mudanças que alteram estado devem mostrar `changed=0` numa segunda execução (idempotência).
- Quando a mudança é específica de uma distro que não tem sandbox (RedHat, Arch), a limitação está registrada no PR.
- A documentação afetada foi atualizada no mesmo PR: `docs/`, e também `README.md` e `USAGE.md` quando o comportamento visível muda. A lista de tags está sincronizada nos lugares listados no `CLAUDE.md`.
- Nenhum documento descreve comportamento obsoleto. O item correspondente do `TECH_DEBT.md` foi removido, e a matriz e as seções do `ARCHITECTURE.md` refletem o novo estado.
- Achados novos e descobertas sobre o sistema feitos durante o trabalho estão documentados em `docs/`, ou registrados como Issue quando são trabalho a fazer.
- CI verde no PR, quando houver CI.

## Fluxo de uma análise ampla

1. Analisar o projeto, sem alterar código de produção.
2. Atualizar a documentação relevante em `docs/`.
3. Identificar os itens de trabalho acionáveis.
4. Buscar Issues existentes, abertas e fechadas recentemente.
5. Criar Issues para os itens ainda não rastreados e colocá-las no board (`Backlog` + `Priority` + `Size`). Ou comentar ou atualizar as Issues existentes.
6. Ligar a documentação e as Issues nos dois sentidos.
7. Reportar as Issues **criadas**, as **atualizadas** e as **intencionalmente não criadas**, com o motivo.

## Commits

- **Sempre [Conventional Commits](https://www.conventionalcommits.org/) / commitlint (config-conventional):** `<type>(<scope opcional>): <descrição>`.
  - Tipos: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.
  - Uma breaking change leva `!` (`feat(docker)!: ...`) e/ou o rodapé `BREAKING CHANGE:`.
  - Releases: `chore(release): vX.Y.Z`.
- A descrição fica **em inglês, no imperativo e em minúsculas**, sem ponto final, com cabeçalho de até 100 caracteres. Exemplo: `fix(makefile): require ip for remote target`, não `fixed`.
- Quando houver Issue, o commit leva o rodapé `Refs #N`. O `Closes #N` fica no corpo do PR.
- Commits pequenos, um por mudança lógica.
- O histórico anterior a esta regra não segue o padrão e **não será reescrito**.

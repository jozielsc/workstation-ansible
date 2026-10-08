# Fluxo de Trabalho: Análise, Documentação e Issues

Regras para qualquer pessoa ou agente que analise, modifique ou evolua este projeto.

## Princípios

- **O backlog oficial são as Issues do GitHub** (`jozielsc/workstation-ansible`). Trabalho identificado em análise vira Issue, não fica só em documento ou conversa.
- **O conhecimento do projeto fica em `docs/`.** O `CLAUDE.md` contém só o essencial e estável e aponta para `docs/`.
- **Analisar não autoriza alterar código.** Durante uma análise, só é permitido documentar e criar ou atualizar Issues. Código de produção (playbooks, roles, Makefile, scripts, perfis) só muda quando a implementação é pedida explicitamente.

## Documentação

Registre em `docs/` toda descoberta relevante: comportamento do sistema, arquitetura, relações de dependência, restrições técnicas, comportamento legado e decisões de design.

| Arquivo | Conteúdo |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Como o sistema funciona: fluxo, precedência de variáveis, tags, roles, integrações, matriz de plataformas |
| [TECH_DEBT.md](TECH_DEBT.md) | Baseline datada de problemas conhecidos, cada item com o nível de evidência e o link para sua Issue |
| [USAGE.md](USAGE.md) | Manual do usuário final |
| `WORKFLOW.md` | Este documento |

- Prefira atualizar um documento existente a criar um novo e redundante.
- Análises extensas vão para `docs/`, nunca para o `CLAUDE.md`.
- Ao corrigir um item do `TECH_DEBT.md`, remova-o ou marque como resolvido, citando o commit ou PR.

## Issues

### Quando criar

Crie uma Issue (`gh issue create`) para trabalho **concreto e acionável** identificado na análise, por exemplo:

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

- O título deve ser claro e específico. Escreva o conteúdo em português, seguindo a convenção do projeto.
- Use apenas labels que já existem no repositório (`gh label list`): `bug`, `enhancement`, `documentation`, `good first issue`, `help wanted`, `question`. Crie labels novas só se pedirem.
- Issues diretamente relacionadas devem ser ligadas pelos relacionamentos do GitHub (sub-issue, ou "blocked by"/"blocks" quando houver dependência real). Na falta disso, cite `#<n>` no corpo da Issue.

### Rastreabilidade

- A documentação aponta para a Issue: no `TECH_DEBT.md`, cada item rastreado leva o link `#<n>`.
- A Issue aponta para a documentação, na seção "Referências".
- PRs que resolvem uma Issue usam `Closes #<n>` na descrição.

## Fluxo de uma análise ampla

1. Analisar o projeto, sem alterar código de produção.
2. Atualizar a documentação relevante em `docs/`.
3. Identificar os itens de trabalho acionáveis.
4. Buscar Issues existentes, abertas e fechadas recentemente.
5. Criar Issues para os itens ainda não rastreados, ou comentar ou atualizar as existentes.
6. Ligar a documentação e as Issues nos dois sentidos.
7. Reportar as Issues **criadas**, as **atualizadas** e as **intencionalmente não criadas**, com o motivo.

## Git

- Mensagens de commit seguem o **commitlint (config-conventional)**: `type(scope): subject`.
  - Tipos: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `ci`, `build`, `perf`, `style`, `revert`.
  - Assunto em minúsculas, sem ponto final, cabeçalho com até 100 caracteres e uma linha em branco antes do corpo.
  - Releases: `chore(release): vX.Y.Z`.
- Mudanças passam por uma branch e por PR para a `main`. Depois do merge, a branch é removida.

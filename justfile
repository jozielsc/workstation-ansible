# Tarefas de desenvolvimento: lint, testes e o sandbox para conferir uma mudança. O provisionamento fica em
# scripts/workstation.sh ("./scripts/workstation.sh help").
# O just vem do grupo dev do uv: rode "uv run just <receita>" (ou "just <receita>" com o .venv ativado).
# "uv run just" sozinho lista as receitas. As receitas rodam na pasta deste arquivo, de qualquer subpasta.

# Uma falha interrompe a receita, inclusive no meio de um pipe.
set shell := ["bash", "-euo", "pipefail", "-c"]

# Cores e saída do Ansible em tempo real, inclusive quando a saída não é um terminal.
export ANSIBLE_FORCE_COLOR := "1"
export PYTHONUNBUFFERED := "1"

# --locked: usa exatamente as versões do uv.lock e falha se ele estiver desatualizado, em vez de re-resolver em
# silêncio.
uv_run := "uv run --locked"

[doc("Lista as receitas.")]
default:
    @{{ quote(just_executable()) }} --list --justfile {{ quote(justfile()) }}

# As mesmas checagens do CI (.github/workflows/ci.yml), em sequência: a primeira que falhar interrompe as seguintes.
# O --syntax-check repete uma regra do ansible-lint, mas é rápido e dá um erro claro antes dele. O yamllint direto
# cobre também o YAML que não é de Ansible (workflows, configs). O shellcheck recebe todo *.sh do git ls-files, em
# qualquer pasta: a lista é a do índice do git, não a do disco. Um script novo ainda sem `git add` só é checado no CI,
# e um .sh apagado sem stage faz o shellcheck falhar com "does not exist". Fora de um clone git, o lint falha logo no
# início, em vez de passar sem checar os scripts.
[doc("Syntax-check, ansible-lint, yamllint e shellcheck (via uv): as mesmas checagens do CI.")]
lint: _require-uv _require-git
    @echo "{{ GREEN }}>> Verificando a sintaxe do playbook...{{ NORMAL }}"
    {{ uv_run }} ansible-playbook playbooks/site.yml --syntax-check -i localhost,
    @echo "{{ GREEN }}>> Executando Ansible Lint...{{ NORMAL }}"
    {{ uv_run }} ansible-lint
    @echo "{{ GREEN }}>> Executando yamllint...{{ NORMAL }}"
    {{ uv_run }} yamllint --strict .
    @echo "{{ GREEN }}>> Executando shellcheck...{{ NORMAL }}"
    git ls-files -z '*.sh' | xargs -0 -r {{ uv_run }} shellcheck

# O molecule é um teste adicional: não substitui o sandbox.
[doc("Executa o cenário molecule (uv run molecule test; cenário pendente na #34).")]
test: _require-uv
    @if ! compgen -G 'molecule/*/molecule.yml' >/dev/null; then \
        echo "Erro: nenhum cenário molecule encontrado (molecule/*/molecule.yml). Veja a issue #34." >&2; \
        exit 1; \
    fi
    @echo "{{ GREEN }}>> Executando testes Molecule...{{ NORMAL }}"
    {{ uv_run }} molecule test

# O just roda as dependências em ordem, uma por vez: o test só roda se o lint passar.
[doc("Executa lint e, se ele passar, test.")]
check: lint test

# Só chama o scripts/workstation.sh, sem lógica própria de docker ou ansible; ele mostra os comandos que executa. Os
# parâmetros chegam ao script como argumentos posicionais ("$@"), sem passar pela interpolação do just no shell. Distro
# e tags vão na forma "--opção valor", em que o script recusa um valor que começa com "-": "just sandbox ubuntu -vv",
# sem as tags, sai com erro em vez de rodar com "--tags=-vv" (só as tarefas "always"). Os argumentos extras vão depois
# de um "--"; um "--" digitado ("just sandbox void go -- -vv") não é repetido. Com
# "uv run", o ansible-playbook do script é o do .venv. A segunda execução no mesmo container, para conferir a
# idempotência, depende da #51.
[doc("Provisiona um container sandbox; distro e tags vêm antes dos argumentos extras do ansible-playbook. Ex.: just sandbox ubuntu rust -vv")]
[positional-arguments]
sandbox distro="void" tags="all" *ansible_args:
    @distro="$1" tags="$2"; shift 2; [ "${1-}" != -- ] || shift; \
        ./scripts/workstation.sh sandbox --distro "$distro" --tags "$tags" ${1+--} "$@"

_require-uv:
    @command -v uv >/dev/null 2>&1 || { \
        echo "Erro: uv não encontrado. Instale-o (https://docs.astral.sh/uv/) e rode 'uv sync'." >&2; \
        exit 1; \
    }

_require-git:
    @git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { \
        echo "Erro: fora de um clone git; o shellcheck do lint usa o git ls-files." >&2; \
        exit 1; \
    }

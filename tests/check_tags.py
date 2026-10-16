"""Confere a lista de tags de scripts/lib/tags (a fonte única do --tags, do help e do wizard).

Falha (código 1) quando:
- uma linha do arquivo (tag e apelidos) não corresponde exatamente às tags de uma role do playbooks/site.yml (sem
  "never") ou de um include de playbooks/roles/languages/tasks/main.yml, ou quando uma role ou um include não tem
  linha correspondente; assim, um apelido na tag errada também falha;
- alguma tag não aparece, como `tag`, nas seções de tags do README.md (PT e EN) e do docs/USAGE.md, ou algum apelido
  não aparece na seção de tags do docs/USAGE.md.

Roda no "just lint": uv run --locked python tests/check_tags.py
"""

import re
import sys
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parent.parent
TAGS_FILE = REPO / "scripts/lib/tags"

# Seções que listam as tags: (arquivo, título da seção, se os apelidos também precisam aparecer). A seção vai até o
# próximo título do mesmo nível ou acima.
DOC_SECTIONS = [
    ("README.md", "### ⚡ Execução Granular por Tags", False),
    ("README.md", "### ⚡ Granular Tag Execution", False),
    ("docs/USAGE.md", "## Tags Disponíveis", True),
]


def read_tags_file():
    """Linhas do arquivo como (tag, [apelidos]), com as mesmas regras do load_tags de scripts/lib/tags.sh."""
    rows = []
    for line in TAGS_FILE.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        fields = line.split("|")
        if len(fields) != 3 or not fields[0].strip():
            sys.exit(f"{TAGS_FILE.relative_to(REPO)}: linha fora do formato tag|descrição|apelidos: {line!r}")
        rows.append((fields[0], fields[2].split()))
    return rows


def as_list(tags):
    """O "tags:" do Ansible aceita uma lista ou um texto (uma tag, ou várias separadas por vírgula)."""
    if tags is None:
        return []
    if isinstance(tags, str):
        return [t.strip() for t in tags.split(",") if t.strip()]
    return [str(t) for t in tags]


def playbook_groups():
    """As tags de cada role do site.yml (sem "never") e de cada include da languages, como conjuntos."""
    groups = []
    play = yaml.safe_load((REPO / "playbooks/site.yml").read_text(encoding="utf-8"))[0]
    for role in play.get("roles", []):
        if isinstance(role, dict):
            groups.append(frozenset(set(as_list(role.get("tags"))) - {"never"}))
    includes = yaml.safe_load((REPO / "playbooks/roles/languages/tasks/main.yml").read_text(encoding="utf-8"))
    for task in includes:
        if isinstance(task, dict) and task.get("tags"):
            groups.append(frozenset(as_list(task["tags"])))
    return [g for g in groups if g]


def section(path, title):
    text = (REPO / path).read_text(encoding="utf-8")
    start = text.find(title + "\n")
    if start < 0:
        return None
    level = len(title) - len(title.lstrip("#"))
    rest = text[start + len(title) + 1 :]
    end = re.search(rf"^#{{1,{level}}} ", rest, flags=re.M)
    return rest[: end.start()] if end else rest


def main():
    errors = []
    rows = read_tags_file()
    names = [name for name, _ in rows]
    aliases = [alias for _, row_aliases in rows for alias in row_aliases]
    everything = names + aliases
    duplicates = sorted({t for t in everything if everything.count(t) > 1})
    if duplicates:
        errors.append(f"tags repetidas em scripts/lib/tags: {', '.join(duplicates)}")

    groups = playbook_groups()
    file_groups = [frozenset([name, *row_aliases]) for name, row_aliases in rows]
    for name, row_aliases in rows:
        group = frozenset([name, *row_aliases])
        if group not in groups:
            errors.append(
                f"scripts/lib/tags: a linha de '{name}' ({', '.join(sorted(group))}) não corresponde às tags de "
                "nenhuma role do site.yml nem de nenhum include da languages"
            )
    for group in groups:
        if group not in file_groups:
            errors.append(f"tags do playbook sem linha correspondente em scripts/lib/tags: {', '.join(sorted(group))}")

    for path, title, with_aliases in DOC_SECTIONS:
        body = section(path, title)
        if body is None:
            errors.append(f"{path}: seção não encontrada: {title}")
            continue
        required = names + (aliases if with_aliases else [])
        if absent := [t for t in required if f"`{t}`" not in body]:
            errors.append(f"{path} ({title}): sem menção: {', '.join(absent)}")

    for error in errors:
        print(f"Erro: {error}", file=sys.stderr)
    if errors:
        return 1
    print(f"Lista de tags conferida: {len(names)} tags e {len(aliases)} apelidos.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

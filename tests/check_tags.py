"""Confere a lista de tags de scripts/lib/tags (a fonte única do --tags, do help e do wizard).

Falha (código 1) quando:
- as tags e os apelidos do arquivo divergem das tags de role do playbooks/site.yml (sem "never") somadas às dos
  includes de playbooks/roles/languages/tasks/main.yml;
- alguma tag do arquivo não aparece, como `tag`, nas seções de tags do README.md (PT e EN) e do docs/USAGE.md.

Roda no "just lint": uv run --locked python tests/check_tags.py
"""

import re
import sys
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parent.parent
TAGS_FILE = REPO / "scripts/lib/tags"

# Seções que listam as tags: (arquivo, título da seção). A seção vai até o próximo título do mesmo nível ou acima.
DOC_SECTIONS = [
    ("README.md", "### ⚡ Execução Granular por Tags"),
    ("README.md", "### ⚡ Granular Tag Execution"),
    ("docs/USAGE.md", "## Tags Disponíveis"),
]


def read_tags_file():
    names, aliases = [], []
    for line in TAGS_FILE.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        fields = line.split("|")
        if len(fields) != 3 or not fields[0]:
            sys.exit(f"{TAGS_FILE.relative_to(REPO)}: linha fora do formato tag|descrição|apelidos: {line!r}")
        names.append(fields[0])
        aliases.extend(fields[2].split())
    return names, aliases


def playbook_tags():
    tags = set()
    play = yaml.safe_load((REPO / "playbooks/site.yml").read_text(encoding="utf-8"))[0]
    for role in play.get("roles", []):
        tags.update(role.get("tags", []))
    includes = yaml.safe_load((REPO / "playbooks/roles/languages/tasks/main.yml").read_text(encoding="utf-8"))
    for task in includes:
        tags.update(task.get("tags", []))
    tags.discard("never")
    return tags


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
    names, aliases = read_tags_file()
    listed = set(names) | set(aliases)
    duplicates = sorted({t for t in names + aliases if (names + aliases).count(t) > 1})
    if duplicates:
        errors.append(f"tags repetidas em scripts/lib/tags: {', '.join(duplicates)}")

    expected = playbook_tags()
    if missing := sorted(expected - listed):
        errors.append(f"tags do playbook que faltam em scripts/lib/tags: {', '.join(missing)}")
    if extra := sorted(listed - expected):
        errors.append(f"tags de scripts/lib/tags que não existem no playbook: {', '.join(extra)}")

    for path, title in DOC_SECTIONS:
        body = section(path, title)
        if body is None:
            errors.append(f"{path}: seção não encontrada: {title}")
            continue
        if absent := [n for n in names if f"`{n}`" not in body]:
            errors.append(f"{path} ({title}): tags sem menção: {', '.join(absent)}")

    for error in errors:
        print(f"Erro: {error}", file=sys.stderr)
    if errors:
        return 1
    print(f"Lista de tags conferida: {len(names)} tags e {len(aliases)} apelidos.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

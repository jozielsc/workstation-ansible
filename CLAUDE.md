# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Ansible project that provisions a Linux developer workstation (Debian/Ubuntu, Void, RedHat/Fedora, Arch). There is no build step; `scripts/workstation.sh` is the entry point and wraps `ansible-playbook playbooks/site.yml`; `./workstation.sh` at the root is a thin wrapper that `exec`s it (passing its own path in `WORKSTATION_PROG` so messages show `./workstation.sh`). Dev tasks (`lint`, `test`, `check`, a `sandbox` shortcut) live in the `justfile` and run with `uv run just <recipe>`; provisioning needs neither uv nor just. Task names, comments, docs and user-facing messages are written in Portuguese — keep that convention.

## Workflow rules

Full rules, board field IDs and `gh` recipes are in `docs/WORKFLOW.md`. Essentials:
- Analysis never authorizes changing production code (playbooks, roles, justfile, scripts, profiles); only documentation and GitHub Issues. Implement only when explicitly asked. Where legacy code diverges from a rule, new or changed code follows the rule; don't fix the legacy without an issue.
- Keep **code ↔ `docs/` ↔ GitHub Issues** consistent at all times: code is the current implementation, `docs/` is the current knowledge (what/how/why), Issues are the remaining actionable work. Don't duplicate between them: Issues reference doc sections for technical context instead of copying it.
- Record architectural discoveries, constraints, legacy behavior and design decisions in the right file under `docs/` (update before creating new docs). A change that alters documented behavior updates the docs in the same PR; never leave docs describing obsolete behavior, and substantial work isn't done until its knowledge is documented. Keep this file concise.
- Before implementing an issue, read it and the relevant docs and check that both still match the code.
- The single backlog is GitHub Project #6 "workstation-ansible" (`gh project item-list 6 --owner jozielsc`). Status flow: `Backlog → Ready → In progress → In review → Done`. Every new issue goes on the board as `Backlog` with `Priority` (P0–P2) and `Size` (XS–XL).
- Before creating an issue, search open and recently closed ones (`gh issue list --state all --search ...`); comment on or update an existing one instead of duplicating. Use the template in `docs/WORKFLOW.md`, only existing labels, GitHub relationships for related issues, and cross-link docs ↔ issues. After an analysis, report the issues created, updated, and intentionally not created.
- One issue → one branch named `<type>-<slug>-<N>`, created from fresh `origin/main` (no `/`, no `gh issue develop`, never without an issue). Put the implementation plan in the issue body (`## Plano de implementação`) and decisions in issue comments.
- PR to `main` with `Closes #N` in the body (never the title); verify with `gh pr view <PR> --json baseRefName,closingIssuesReferences`. Review in rounds with `/code-review <PR> --comment`; ask the user before applying fixes; unfixed relevant findings become new issues.
- Merge only when the user explicitly asks. Afterwards: card to `Done`, confirm the issue closed, delete the local and remote branch. Check card status after any link, merge or close (board automations move cards).
- Commits follow Conventional Commits / commitlint: `type(scope): description` in English, imperative, lowercase; `Refs #N` footer when there is an issue.

Deeper references:
- `docs/WORKFLOW.md` — analysis, documentation, issue and git workflow.
- `docs/ARCHITECTURE.md` — execution flow, variable precedence, tag semantics, per-role behavior, external integrations, platform support matrix.
- `docs/TECH_DEBT.md` — dated technical baseline: known bugs, duplications, risks. Check it before "fixing" something, and update it when an item is resolved.
- `docs/USAGE.md` — end-user manual (also shown by `scripts/workstation.sh help-docs` and the wizard).

## Commands

```bash
W=./scripts/workstation.sh   # shorthand used below; the script runs from any directory
$W                           # interactive TUI wizard (scripts/interactive.sh -> builds and runs a workstation.sh command)
$W local                     # provision localhost (asks for sudo password via -K)
$W local --tags zsh,node     # run only selected roles/subtasks
$W local --dry-run           # --check --diff
$W local --profile local     # load profiles/local.yml as the main profile
$W remote --ip x.x.x.x --user root      # --user defaults to whoami
$W tunnel --ip ... --user ... --jump-ip ... --jump-user ...
$W local -- -vvv             # args after -- are appended to ansible-playbook
$W <command> ... --print     # print the exact commands without running them
$W help                      # commands and options
uv run just                  # list the dev recipes (just comes from the uv dev group)
uv run just lint             # syntax-check + ansible-lint + yamllint + shellcheck + tag list check (via uv)
uv run just test             # uv run molecule test (scenario pending: #34)
uv run just check            # lint, then test
uv run just sandbox ubuntu rust -vv  # shortcut for workstation.sh sandbox --distro ubuntu --tags rust -- -vv

# Static checks that never touch a host
ansible-playbook playbooks/site.yml --syntax-check -i localhost,
ansible-playbook playbooks/site.yml --list-tasks --tags rust -i localhost,
```

Testing is done in disposable Docker containers, never on the host:

```bash
./scripts/workstation.sh sandbox                              # Void Linux glibc (default)
./scripts/workstation.sh sandbox --distro ubuntu --tags rust  # test a single tag on Ubuntu
./scripts/workstation.sh sandbox --distro ubuntu --tags rust --reuse  # rerun in the same container (idempotence)
./scripts/workstation.sh sandbox-shell --distro void          # inspect the container afterwards
./scripts/workstation.sh sandbox-clean --distro void
```

`sandbox` builds `tests/sandbox/Dockerfile.<distro>`, recreates the container, and runs the playbook against it with `-c docker -u dev` (passwordless sudo, no `-K`); `--reuse` skips the build and recreation and reruns in the existing container (the idempotence check). With `--dry-run` it runs in `--check --diff` against the recreated container, or against the existing one with `--reuse`. The containers have no init system (runit/systemd not PID 1), so service-enablement paths are skipped there and are never exercised by the sandbox. Dockerfiles exist for `void`, `ubuntu`, `fedora` and `arch`. CI (`.github/workflows/ci.yml`) only runs `uv run --locked just lint` on PRs and pushes to `main`; the sandbox has no CI yet (#29).

Dev tools (ansible, ansible-lint, yamllint, shellcheck-py, molecule, plus PyYAML for `tests/check_tags.py`) come from the uv `dev` group in `pyproject.toml` (`uv sync`); run them via `uv run` / `uv run just lint|test|check`. The `justfile` only holds dev tasks; recipes run with `bash -euo pipefail` in the repo root, and `sandbox` just forwards to `scripts/workstation.sh` (no docker/ansible logic of its own). Molecule is an additional test layer: it does **not** replace the sandbox matrix (#29) or the lint CI unless the maintainer says so.

## Architecture

- `playbooks/site.yml` is the only playbook. Its `pre_tasks` (all tagged `always`):
  1. assert ansible-core ≥ `min_ansible_core_version` (2.13, play `vars:`), on the controller before touching the host (dnf5 targets, Fedora ≥ 41, also need 2.15.11+/2.16.6+/2.17+, checked after the minimal `setup`);
  2. load `profiles/{{ profile }}.yml`, then `profiles/local.yml` if present (gitignored; skipped via `when: … is file or … is link`, but an invalid file or broken symlink fails the play);
  3. gather facts (the play has `gather_facts: false`): first a minimal `setup` without become, then fail unless `ansible_facts['os_family']` is in `supported_os_families` (play `vars:`; the same four families as the `vars/<os_family>.yml` files, so a new family goes in both; `allow_unsupported_distro: true` via `local.yml` or `-e` skips it with a warning), then the full `setup` with become; on `dnf5` hosts (Fedora ≥ 41), ensure `python3-libdnf5` (installed if missing, a failed install only warns; a `--dry-run` without it stops with a message);
  4. compute `user_home` and `user_id` by running `echo $HOME && whoami` with `become: false`. The play runs with `become: true`, so **any task that touches the user's home must use `become: false` and `user_home`/`user_id`**, never `ansible_env.HOME` or `ansible_user`.
- Roles run in order: `devtools`, `languages`, `docker`, `zsh`, `ui`, `editors`, `dotfiles`. The `ui` role carries the `never` tag, so it only runs when `--tags ui` (or another of its tags) is passed explicitly.
- **Per-distro package lists**: roles that install packages (`devtools`, `editors`, `ui`) do `include_vars: "{{ ansible_facts['os_family'] }}.yml"` from their `vars/` dir (`Debian`, `Void`, `RedHat`, `Archlinux`), with a hardcoded fallback list if the file is missing. Package names differ between distros, so adding a package usually means editing all four files.
- **Variable precedence**: the role-level `include_vars` runs after the profile's, so the distro file wins. A profile can't replace `devtools_packages`/`editors_packages`/`ui_packages`; it can only add via `*_extra_packages`. Dict variables (`*_features`) are replaced, not merged (default `hash_behaviour`), so a profile that sets one key of a features dict drops the others.
- **Resilient install pattern**: the base list is merged with `*_extra_packages` from the profile, then installed in a `block` as one batch; on failure the `rescue` installs packages one by one with `failed_when: false` and reports the missing ones. Reuse this pattern for new package-installing roles rather than letting one unavailable package abort the run.
- **Feature toggles** live in profiles (`devtools_features`, `languages_features`, `ui_features`, `editors_features`) and are read with `| default(...)` in `when:` clauses.
- **Tags**: role tags from `site.yml` are inherited by every task in the role, including tasks pulled in by `include_tasks`. Tags placed on an `include_tasks` statement are **not** inherited by the included tasks, and an included task's own tag can't be selected unless the include itself matches. Each language in `roles/languages/tasks/` is an include tagged `python`, `node`, `rust` or `go`/`golang`, and its tasks must repeat that tag to run under it.
- Distro branching beyond package names uses `ansible_facts['os_family']` or `ansible_facts['distribution'] == "Void"` (e.g. `roles/docker/tasks/{debian,void}.yml`). On Void, Ansible reports `service_mgr` as `service`; services are enabled by symlinking `/etc/sv/<name>` into `/var/service`.
- External installers are idempotent and tolerate network failures: rustup uses `creates:`/`stat` and falls back to the distro package; the lazygit binary compares `lazygit --version` with the latest release, downloads only when it is missing or older, turns a network/rate-limit/5xx failure into a warning and fails the play on any other error (no distro fallback).
- `dotfiles` clones `dotfiles_repos` (default: `jozielsc/dotfiles` into `~/.dotfiles`) and stows each top-level directory with `--no-folding`. It deliberately does **not** use `stow --adopt` (that would overwrite tracked dotfiles with whatever is in `$HOME`); conflicts are reported and skipped instead of failing the play. Because it runs last, anything earlier roles write into `$HOME` (e.g. shell rc files) can turn into stow conflicts.
- **Tag list**: the single source is `scripts/lib/tags` (`tag|description|aliases`), read by the `help`, the wizard and the `--tags` validation of `scripts/workstation.sh` (unknown tags exit 2). `tests/check_tags.py`, run by `just lint`, fails when it diverges from the role tags in `site.yml` plus the `languages` includes, or when `README.md` (PT and EN) or `docs/USAGE.md` miss a tag. When you add or rename a tag, update `site.yml`/the include, `scripts/lib/tags`, the README and USAGE. When you add a `scripts/workstation.sh` option, update its `help`, `docs/USAGE.md`, the README and this file.
- `scripts/interactive.sh` is a dialog/whiptail/plain-CLI wizard (behind an engine-agnostic `ui_*` layer) that only assembles `scripts/workstation.sh` arguments (mode, profile, tags, dry-run, target) and runs the script. It has no provisioning logic of its own.
- `scripts/workstation.sh` has one function per command (`run_local`, `run_remote`, …) and only validates options and builds the `ansible-playbook`/`docker` commands. It is a bash script (shebang), so it works when called from bash or zsh; the wizard requires bash ≥ 4.4.

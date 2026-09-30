---
name: bootstrap-script
description: Bootstrap a new or existing script-only project. Creates the main script, .editorconfig, .shellcheckrc (not fish), and standard project files (AI.md, IDEA.md, AGENTS.md, .gitignore, README.md, LICENSE.md). No workflows, no toolchain, no Makefile. Auto-invoke when user asks to create/init a script project, install script, or setup script.
---

# Bootstrap a Script Project

Bootstrap a script-type project in `{project_dir}`. Script projects contain one or more shell scripts — no compiled binaries, no CI workflows, no toolchain images.

## Step 1 — Resolve arguments

Parse `the requested scope` as: `[shell] [script-name]`

**Shell** (first arg, optional):
- Accepted values: `sh`, `bash`, `zsh`, `fish`
- Default: `sh` (POSIX)
- If omitted, scan `{project_dir}` for existing script files (`*.sh`, `*.bash`, `*.zsh`, `*.fish`, and shebanged files without extension):
  - **Exactly one found** → detect shell from its shebang first (`#!/usr/bin/env bash` → bash, `#!/usr/bin/env zsh` → zsh, `#!/usr/bin/env fish` → fish, `#!/bin/sh` → sh), then fall back to extension (`.sh` → sh, `.bash` → bash, `.zsh` → zsh, `.fish` → fish). Use that file as the primary script.
  - **Multiple found** → ask the user which is the primary script before continuing; do not guess.
  - **None found** → default to `sh`.

**Script name** (second arg, optional):
- Default: `install.sh` for sh/bash, `install.zsh` for zsh, `install.fish` for fish
- Extension rules: bash/sh → `.sh`; zsh → `.zsh`; fish → `.fish`
- If a name is given without extension, append the correct extension for the shell.
- If an existing script was detected in the shell resolution step above, that file's name becomes the default — no need to re-specify it.

**Project idea** (empty repo only):

After resolving shell and script name, check whether `{project_dir}` contains any files other than `.git/` and its contents. If the directory is effectively empty:
- Ask the user: *"What does this project do? Give me a sentence or two describing its purpose and who it's for."*
- Use the response to populate `@@Description` in the script header, the one-sentence description in `AI.md`, the opening paragraph in `IDEA.md`, and the description paragraph in `README.md`.
- If the directory already has files (existing script, README, etc.), infer the description from those instead — do not ask.

## Step 2 — Create the script file

If the script file does not already exist, create it. If it exists, leave it untouched.

Use the header template from `~/.codex/memory/script_conventions.md`. Fill in:
- `{shell}` — resolved shell name
- `##@Version` and `VERSION=` — run `date +'%Y%m%d%H%M-git'` and use the result
- `@@Created` — current date/time in full weekday format: e.g. `Monday, May 19, 2026 14:30 EDT`
- `@@File` — the script filename
- `@@Description` — one sentence describing what the script does (infer from name; ask if unclear)
- `@@Template` — `shell/{shell}`
- All other `@@` fields — leave empty (just the field label, no value)

After the header, add the standard boilerplate variables for the resolved shell (see `~/.codex/memory/script_conventions.md` Shell-specific differences table). Then add `set -euo pipefail` (bash/zsh) or `set -eu` (sh). Fish gets neither.

**ENV var naming and shadowing rules — enforced always:**

All project env vars must be `{PROJECT_NAME}_VARNAME` — uppercase, underscores only, actual script/project name as prefix. Never generic prefixes (`APP_`, `MY_`, `SCRIPT_`, etc.), never hyphens.

```sh
# WRONG — shadows system env / uses generic prefix
HOSTNAME="$(hostname -f)"
USER="admin"
APP_FQDN="myhost.example.com"

# CORRECT — project-prefixed, system var used as fallback
MYSCRIPT_FQDN="${MYSCRIPT_FQDN:-$(hostname -f)}"
MYSCRIPT_DOMAIN="${MYSCRIPT_DOMAIN:-$(hostname -d)}"
RUN_USER="${SUDO_USER:-${USER}}"
```
System env vars — read freely as fallbacks anywhere; overwriting rules by category:

**Shell mechanics — never overwrite:** `PS1`–`PS4`, `OPTIND`, `OPTARG`, `SHLVL`, all `BASH_*`/`ZSH_*`/`FISH_*` vars.
Exception: `IFS` may be temporarily changed — save and restore, or scope to a subshell:

```sh
old_IFS="$IFS"; IFS=:
# ... use IFS ...
IFS="$old_IFS"

# or subshell-scoped
( IFS=$'\n'; ... )
```

**Process identity — never overwrite:** `HOME`, `USER`, `LOGNAME`, `SHELL`, `UID`, `EUID`, `GID`, `PATH`, `PWD`, `OLDPWD`.

**Environment preferences — overwrite only when intentional:** `LANG`, `TZ`, `TERM`, `EDITOR`, `VISUAL`, `PAGER`, `HOSTNAME`, `HOST`. Prefer a project-prefixed var for project-specific values; only overwrite when downstream processes must inherit it:

```sh
# CORRECT — read system vars as fallbacks; project-prefixed names hold values
RUN_USER="${SUDO_USER:-$USER}"
MYSCRIPT_FQDN="${MYSCRIPT_FQDN:-$(hostname -f)}"
MYSCRIPT_DOMAIN="${MYSCRIPT_DOMAIN:-$(hostname -d)}"

# OK — store in project var first, then assign system var from it
MYSCRIPT_LANG="${MYSCRIPT_LANG:-en_US.UTF-8}"
MYSCRIPT_TZ="${MYSCRIPT_TZ:-UTC}"
export LANG="${MYSCRIPT_LANG}"
export TZ="${MYSCRIPT_TZ}"
```

When an external app or tool expects a specific variable name (e.g. `DATABASE_URL`, `PGPASSWORD`), bridge from the project var and export only if required:

```sh
# CORRECT — adapter set immediately before the call that needs it
export DATABASE_URL="${MYAPP_DATABASE_URL}"
some-external-tool
```

Never set these adapters at top-level unless the entire script is a thin wrapper.

**Sane fallbacks** — every project var should have a `${VAR:-default}`. Build compound defaults from earlier vars:

```sh
MYSCRIPT_FQDN="${MYSCRIPT_FQDN:-$HOSTNAME}"
MYSCRIPT_DOMAIN="${MYSCRIPT_DOMAIN:-$(hostname -d)}"
MYSCRIPT_ADMIN_NAME="${MYSCRIPT_ADMIN_NAME:-administrator}"
MYSCRIPT_ADMIN_EMAIL="${MYSCRIPT_ADMIN_EMAIL:-${MYSCRIPT_ADMIN_NAME}@${MYSCRIPT_FQDN}}"
MYSCRIPT_EMAIL_FROM_ADDRESS="${MYSCRIPT_EMAIL_FROM_ADDRESS:-no-reply@${MYSCRIPT_FQDN}}"
MYSCRIPT_EMAIL_FROM_NAME="${MYSCRIPT_EMAIL_FROM_NAME:-My Application}"
MYSCRIPT_PORT="${MYSCRIPT_PORT:-62080}"
MYSCRIPT_LOG_LEVEL="${MYSCRIPT_LOG_LEVEL:-info}"
MYSCRIPT_DATA_DIR="${MYSCRIPT_DATA_DIR:-/var/lib/myscript}"
```

Exceptions — no `${VAR:-literal}` fallback:
- **Secrets/credentials** (`MYSCRIPT_DB_PASSWORD`, `MYSCRIPT_API_KEY`, `MYSCRIPT_SECRET_KEY`) — generate with `__random_password`; if the script is idempotent, save with `__save_credential` (perms `600`, owned by `$RUN_USER:$RUN_USER` or `root:root` depending on context) and show once on first generation:
  ```sh
  CRED_FILE="${MYSCRIPT_CONFIG_DIR:-/etc/myscript}/.credentials"
  MYSCRIPT_DB_PASSWORD="$(__load_credential "$CRED_FILE" MYSCRIPT_DB_PASSWORD)" || {
    MYSCRIPT_DB_PASSWORD="$(__random_password)"
    __save_credential "$CRED_FILE" MYSCRIPT_DB_PASSWORD "$MYSCRIPT_DB_PASSWORD"
  }
  ```
- **Destructive targets** (`MYSCRIPT_BACKUP_DEST`, `MYSCRIPT_DEPLOY_TARGET`) — a wrong default silently operates on the wrong location; `exit 1` with a clear error if unset
- **External service addresses in multi-env deployments** (`MYSCRIPT_DB_HOST`) — defaulting to `localhost` silently breaks in production; `exit 1` with a clear error if unset

End the script with the vim modeline (`# ex: ts=2 sw=2 et filetype={vim-filetype}`) — see `~/.codex/memory/script_conventions.md` for the filetype per shell.

## Step 3 — Create .editorconfig

If `.editorconfig` does not already exist, create it using the template below (verbatim — do not alter content):

```
Read `editorconfig.template` from this skill folder and copy its contents into the project root.
```

## Step 4 — Create .shellcheckrc

Skip entirely if shell is `fish`.

If `.shellcheckrc` does not already exist, create it using the template below, then change the `shell=` line to match the target shell:
- `sh` → `shell=sh`
- `bash` → `shell=bash`
- `zsh` → `shell=bash` (shellcheck has no native zsh support; bash is the closest valid value)

Template:
```
Read `shellcheckrc.template` from this skill folder and copy its contents into the project root.
```

## Step 5 — Create standard project files

Create only the files that do not already exist. Never overwrite.

**.gitignore** — standard ignores for a shell script project:
```
**/.no_push
.no_git
.installed
.env
app.env
default.env
*.local
.codex/config.toml
.codex/.credentials.json
.codex/backups/
.codex/cache/
.codex/file-history/
.codex/history.jsonl
.codex/projects/
.codex/statsFile
.codex/*.lock
```

**AGENTS.md** — minimal loader:
```markdown
# {project_name}

Read `AI.md` and `IDEA.md` before acting on this project.
```

**AI.md** — minimal spec stub (fill `{project_name}` from the directory name):
```markdown
# {project_name} — AI Spec

## PART 0 — Project Identity

- **Name:** {project_name}
- **Type:** shell script
- **Shell:** {shell}
- **Primary script:** {script_name}
- **Description:** {one-sentence description}
```

**IDEA.md** — stub:
```markdown
# {project_name} — Project Description

{One paragraph: what this script does, for whom, and why it exists.}
```

**README.md** — minimal stub following canonical section order from `~/.codex/memory/project_files.md`:
```markdown
# {project_name}

{One-paragraph description.}

---

## 📦 Install

\`\`\`sh
curl -LSs https://raw.githubusercontent.com/{org}/{project_name}/main/{script_name} \
  -o /usr/local/bin/{script_name_no_ext} && chmod +x /usr/local/bin/{script_name_no_ext}
\`\`\`

---

## 🛠️ Development

\`\`\`sh
# Clone and run directly
git clone https://github.com/{org}/{project_name}
./{script_name} --help
\`\`\`

---

## 📄 License

MIT — see [LICENSE.md](LICENSE.md)
```

**LICENSE.md** — MIT license with current year and author `Jason Hempstead, Casjays Developments`.

## Step 6 — Stage files (git repos only)

Apply the global git gate rule: if `{project_dir}/.git` does not exist, skip all git operations entirely.

If `{project_dir}/.git` exists, run `git add -A` to stage all new and modified files. Do not commit — let the user run `gitcommit` when ready.

## Step 7 — Report

List every file created (or "already existed — skipped") in a compact table. Note any fields in AI.md/IDEA.md/README.md that need the user's input.

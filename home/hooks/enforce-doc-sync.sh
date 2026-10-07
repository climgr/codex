#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202610070001-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  enforce-doc-sync.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Sunday, Sep 27, 2026 EDT
# @@File             :  enforce-doc-sync.sh
# @@Description      :  PreToolUse Bash hook: blocks `gitcommit --dir <path> all` unless .git/COMMIT_MESS carries an explicit IDEA.md and README.md status line, for any repo where that file exists.
# @@Changelog        :  20261007: Scan shell -c commands behind common wrappers.
# @@TODO             :  None
# @@Other            :  Forced-acknowledgment gate, not a content-diff heuristic: only checks that a status line is PRESENT, never that its claim is true (same trust model as enforce-commit-mess-coverage.sh's per-file bullets). Accepted forms: `- IDEA.md: updated (...)` or `- IDEA.md: N/A - no user-facing change` (same for README.md). DOC_SYNC_GATE_OVERRIDE=1 <gitcommit ...> bypasses for that one call - user-directed only, never Codex's own initiative.
# @@Resource         :  AGENTS.md - Commit Workflow · home/memory/gitcommit_conventions.md · home/memory/project_conventions.md
# @@Terminal App     :  no
# @@sudo/root        :  no
# @@Template         :  shell/bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC1001,SC1003,SC2001,SC2003,SC2016,SC2031,SC2090,SC2115,SC2120,SC2155,SC2199,SC2229,SC2317,SC2329
# - - - - - - - - - - - - - - - - - - - - - - - - -
VERSION="202610070003-git"
# - - - - - - - - - - - - - - - - - - - - - - - - -
set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  printf 'enforce-doc-sync.sh: required command not found: python3 (hook disabled, failing open)\n' >&2
  exit 0
fi

ENFORCE_DOC_SYNC_INPUT="$(cat)"

ENFORCE_DOC_SYNC_INPUT_TMPFILE="$(mktemp)"
trap 'rm -f "$ENFORCE_DOC_SYNC_INPUT_TMPFILE"' EXIT
printf '%s' "$ENFORCE_DOC_SYNC_INPUT" > "$ENFORCE_DOC_SYNC_INPUT_TMPFILE"

python3 - "$ENFORCE_DOC_SYNC_INPUT_TMPFILE" <<'PYEOF'
import json
import os
import re
import shlex
import sys


def split_shell_commands(text):
    operators = ("&&", "||", "\n", ";", "|", "&")
    parts, start, quote, escaped, comment, i = [], 0, None, False, False, 0
    while i < len(text):
        char = text[i]
        if comment:
            if char == "\n":
                parts.append(text[start:i])
                start, comment = i + 1, False
            i += 1
            continue
        if escaped:
            escaped = False
            i += 1
            continue
        if quote:
            if quote == '"' and char == "\\":
                escaped = True
            elif char == quote:
                quote = None
            i += 1
            continue
        if char == "\\":
            escaped = True
            i += 1
            continue
        if char in ("'", '"'):
            quote = char
            i += 1
            continue
        if char == "#" and (i == 0 or text[i - 1].isspace() or text[i - 1] in ";&|"):
            comment = True
            i += 1
            continue
        operator = next((op for op in operators if text.startswith(op, i)), None)
        if operator:
            parts.append(text[start:i])
            i += len(operator)
            start = i
            continue
        i += 1
    parts.append(text[start:])
    return expand_shell_commands(parts)


def expand_shell_commands(parts):
    shells = {"bash", "sh", "zsh", "dash", "ksh", "mksh", "ash", "fish"}
    expanded = []
    pending = list(parts)
    while pending:
        part = pending.pop(0)
        try:
            tokens = shlex.split(part, comments=True)
        except ValueError:
            expanded.append(part)
            continue
        index = 0
        while index < len(tokens):
            name = os.path.basename(tokens[index].lstrip("\\"))
            if name in shells:
                break
            if name in ("command", "builtin", "exec", "nohup", "time"):
                if name == "command" and index + 1 < len(tokens) \
                        and tokens[index + 1] in ("-v", "-V"):
                    index = len(tokens)
                    break
                index += 1
                if index < len(tokens) and tokens[index] == "--":
                    index += 1
                continue
            if name == "env":
                index += 1
                while index < len(tokens):
                    token = tokens[index]
                    if token == "--":
                        index += 1
                        break
                    if token in ("-u", "--unset", "-C", "--chdir"):
                        index += 2
                    elif token.startswith("-") or re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", token):
                        index += 1
                    else:
                        break
                continue
            if name in ("sudo", "doas"):
                index += 1
                value_options = {"-u", "--user", "-g", "--group", "-h", "--host",
                                 "-p", "--prompt", "-C", "--close-from", "-r", "--role",
                                 "-t", "--type"}
                while index < len(tokens):
                    token = tokens[index]
                    if token in value_options:
                        index += 2
                    elif token.startswith("--") and "=" in token:
                        index += 1
                    elif token.startswith("-") or re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", token):
                        index += 1
                    else:
                        break
                continue
            if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tokens[index]):
                index += 1
                continue
            index = len(tokens)
            break
        if index >= len(tokens) or os.path.basename(tokens[index].lstrip("\\")) not in shells:
            expanded.append(part)
            continue
        script = None
        for option_index, token in enumerate(tokens[index + 1:], index + 1):
            if token in ("-c", "--command") and option_index + 1 < len(tokens):
                script = tokens[option_index + 1]
                break
            if token.startswith("--command="):
                script = token.split("=", 1)[1]
                break
            if token.startswith("-") and not token.startswith("--") and "c" in token[1:] \
                    and option_index + 1 < len(tokens):
                script = tokens[option_index + 1]
                break
        if script is None:
            expanded.append(part)
        else:
            pending[0:0] = split_shell_commands(script)
    return expanded


with open(sys.argv[1], "r", encoding="utf-8", errors="replace") as _f:
    raw = _f.read()
try:
    payload = json.loads(raw, strict=False)
except Exception:
    sys.exit(0)

if not isinstance(payload, dict):
    sys.exit(0)

if "tool_input" in payload and not isinstance(payload["tool_input"], dict):
    payload["tool_input"] = {}

for _obj in (payload, payload.get("tool_input") or {}):
    for _key in ("command", "cwd", "session_id", "transcript_path"):
        if _key in _obj and not isinstance(_obj[_key], str):
            _obj[_key] = ""

if payload.get("tool_name", "") != "Bash":
    sys.exit(0)

cmd = payload.get("tool_input", {}).get("command", "")
if not cmd or not re.search(r"\bgitcommit\b", cmd):
    sys.exit(0)


def find_gitcommit_dir(text):
    # Only the valid `gitcommit --dir <path> all` shape carries a --dir path -
    # malformed shapes are already blocked by enforce-gitcommit-shape.sh.
    for sub_cmd in split_shell_commands(text):
        sub_cmd = sub_cmd.strip()
        if not sub_cmd:
            continue
        try:
            tokens = shlex.split(sub_cmd, comments=True)
        except ValueError:
            tokens = sub_cmd.split()

        clean = []
        override = False
        skipping_prefix = True
        for tok in tokens:
            if skipping_prefix:
                if tok in ("command", "env", "exec", "nohup", "time", "sudo", "doas"):
                    continue
                if tok == "DOC_SYNC_GATE_OVERRIDE=1":
                    override = True
                    continue
                if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tok):
                    continue
                if tok.startswith("-"):
                    continue
                skipping_prefix = False
            clean.append(tok.lstrip("\\"))

        if len(clean) == 4 and clean[0] == "gitcommit" and clean[1] == "--dir" \
                and clean[3] == "all" and clean[2].startswith("/"):
            yield clean[2], override


targets = list(find_gitcommit_dir(cmd))
if not targets:
    sys.exit(0)

# DOC_SYNC_GATE_OVERRIDE=1 <gitcommit ...> - explicit, per-invocation, user-
# directed bypass. Codex sets this prefix only when the user's own message
# explicitly says to bypass/skip the doc-sync gate for this commit - never on
# its own initiative just because the gate blocked (AGENTS.md: "never
# auto-bypass a hook block"). Same prefix pattern as
# enforce-test-lint-gate.sh's TEST_LINT_GATE_OVERRIDE=1.
if any(override for _target, override in targets):
    sys.exit(0)


def status_line_present(mess_text, filename):
    # Accepted forms:
    #   - IDEA.md: updated (added X to Business Logic)
    #   - IDEA.md: N/A - no user-facing change
    # Presence-only check - it never verifies the claim is true, same trust
    # model as enforce-commit-mess-coverage.sh's per-file `- path:` bullets.
    pattern = r"^\s*-\s*`?" + re.escape(filename) + r"`?\s*:\s*\S"
    for line in mess_text.split("\n"):
        if re.match(pattern, line):
            return True
    return False


problems = []
for repo, _override in targets:
    if not os.path.isdir(os.path.join(repo, ".git")):
        continue
    required = [f for f in ("IDEA.md", "README.md") if os.path.isfile(os.path.join(repo, f))]
    if not required:
        continue
    mess_path = os.path.join(repo, ".git", "COMMIT_MESS")
    try:
        with open(mess_path, "r", encoding="utf-8", errors="replace") as f:
            mess = f.read()
    except OSError:
        mess = ""
    missing = [f for f in required if not status_line_present(mess, f)]
    if missing:
        problems.append((repo, missing))

if not problems:
    sys.exit(0)

msg = "BLOCKED: gitcommit is missing a doc-sync status line in COMMIT_MESS.\n\n"
for repo, missing in problems:
    msg += f"{repo}: missing status line for: {', '.join(missing)}\n"
msg += (
    "\nEvery commit must record, for each doc that exists in the repo, whether "
    "it needed updating - this is what closes the IDEA.md/code drift problem "
    "(a feature gets added to code but IDEA.md never gets told). Add one line "
    "per missing file to .git/COMMIT_MESS, either form:\n"
    "  - IDEA.md: updated (<what changed in Business Logic>)\n"
    "  - IDEA.md: N/A - no user-facing change\n"
    "  - README.md: updated (<what changed>)\n"
    "  - README.md: N/A - no user-facing change\n"
    "This only checks the line is present, not that the claim is accurate - "
    "make the real call before writing it. DOC_SYNC_GATE_OVERRIDE=1 prefix "
    "bypasses this for one call, user-directed only, never on your own "
    "initiative.\n"
)
print(msg)
sys.stderr.write(msg + "\n")
sys.exit(2)
PYEOF

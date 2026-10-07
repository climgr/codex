#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202610070001-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  no-read-gitcommit.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Sunday, August 30, 2026 20:00 EDT
# @@File             :  no-read-gitcommit.sh
# @@Description      :  PreToolUse Read+Grep+Bash hook: blocks reading the commit wrapper script (Read/Grep tools, cat/less/head/etc via Bash), a previously prose-only rule.
# @@Changelog        :  20261007: Scan shell -c commands behind common wrappers.
# @@TODO             :  None
# @@Other            :  Resolves the symlink target so both paths are blocked; the zone's raw-git pre-authorization never covers the commit wrapper itself.
# @@Resource         :  AGENTS.md - Commit Workflow, home/hooks/drift-guard-read.sh
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
  printf 'no-read-gitcommit.sh: required command not found: python3 (hook disabled, failing open)\n' >&2
  exit 0
fi

NO_READ_GITCOMMIT_INPUT="$(cat)"

NO_READ_GITCOMMIT_INPUT_TMPFILE="$(mktemp)"
trap 'rm -f "$NO_READ_GITCOMMIT_INPUT_TMPFILE"' EXIT
printf '%s' "$NO_READ_GITCOMMIT_INPUT" > "$NO_READ_GITCOMMIT_INPUT_TMPFILE"

python3 - "$NO_READ_GITCOMMIT_INPUT_TMPFILE" <<'PYEOF'
import json
import os
import re
import shlex
import shutil
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

# A JSON scalar or array parses cleanly but has no .get(), so the block
# below would raise AttributeError and exit non-zero. Part 6 requires a
# hook to fail open on any unusable payload, never to surface an error.
if not isinstance(payload, dict):
    sys.exit(0)

# Same reasoning one level down: normalise a non-object tool_input /
# tool_response to an empty dict so every downstream .get() chain below
# stays safe without each call site needing its own type check.
for _field in ("tool_input", "tool_response"):
    if _field in payload and not isinstance(payload[_field], dict):
        payload[_field] = {}

# Every field below is documented as a string but arrives as arbitrary JSON.
# A list `command` or a numeric `cwd` reaches a str-only call (.split(),
# .startswith(), os.path.*) and raises TypeError -> exit 1, which Codex
# reports as a hook error on an ordinary tool call. Drop any non-string value
# so the hook no-ops on it instead, per Part 6's "Fail open, always".
for _obj in (payload, payload.get("tool_input") or {}, payload.get("tool_response") or {}):
    for _key in ("command", "file_path", "cwd", "session_id", "transcript_path",
                 "content", "new_string", "old_string", "pattern", "path",
                 "agent_type", "last_assistant_message"):
        if _key in _obj and not isinstance(_obj[_key], str):
            _obj[_key] = ""

tool_name = payload.get("tool_name", "")

# gitcommit_conventions.md:7 forbids hardcoding the gitcommit path (e.g.
# /usr/local/bin/gitcommit) verbatim - it may live in ~/.local/bin,
# /usr/bin, or elsewhere depending on the machine, and "it's always in
# PATH" per that same rule. Resolve it from PATH instead of a fixed list.
GITCOMMIT_RESOLVED = None
_which = shutil.which("gitcommit")
if _which:
    GITCOMMIT_RESOLVED = os.path.realpath(_which)


def is_gitcommit_path(path):
    if not path or not GITCOMMIT_RESOLVED:
        return False
    resolved = os.path.realpath(path)
    return path == GITCOMMIT_RESOLVED or resolved == GITCOMMIT_RESOLVED


msg = (
    "BLOCKED: reading the gitcommit script file is forbidden.\n\n"
    "AGENTS.md's Commit Workflow: \"Never read the gitcommit script file -\n"
    "it is pre-approved and trusted.\" It is invoked, never inspected."
)

if tool_name == "Read":
    file_path = payload.get("tool_input", {}).get("file_path", "") or ""
    if is_gitcommit_path(file_path):
        print(msg)
        sys.stderr.write(msg + "\n")
        sys.exit(2)
    sys.exit(0)

if tool_name == "Grep":
    grep_path = payload.get("tool_input", {}).get("path", "") or ""
    if is_gitcommit_path(grep_path):
        print(msg)
        sys.stderr.write(msg + "\n")
        sys.exit(2)
    sys.exit(0)

if tool_name != "Bash":
    sys.exit(0)

cmd = payload.get("tool_input", {}).get("command", "")
if not cmd or not re.search(r"gitcommit", cmd):
    sys.exit(0)

# Display/pager/editor verbs only — matches AI.md's "cat/less/head/etc."
# row (Part 6, Hook Scripts table). cp/diff read the file too but they
# are file-manipulation/comparison tools, not display tools, so they are
# out of this rule's scope per the audit's Priority 2 classification.
READ_VERBS = {"cat", "less", "more", "head", "tail", "vim", "vi", "nano",
              "view", "bat", "sed", "awk", "grep", "rg", "xxd", "od",
              "strings", "nl", "tac", "cut", "wc", "file", ".", "source"}

# `$(command -v gitcommit)`, `` `which gitcommit` ``, `$(type -P gitcommit)`
# and their whitespace variants all expand to the resolved gitcommit path.
RESOLVER_SUBST_RE = re.compile(
    r"(?:\$\(|`)\s*(?:\\?command\s+-v|\\?which|\\?type\s+-[pP])\s+\\?gitcommit\b"
)

for sub_cmd in split_shell_commands(cmd):
    sub_cmd = sub_cmd.strip()
    if not sub_cmd:
        continue
    try:
        tokens = shlex.split(sub_cmd, comments=True)
    except ValueError:
        tokens = sub_cmd.split()

    clean = []
    skipping_prefix = True
    for tok in tokens:
        if skipping_prefix:
            if tok in ("command", "env", "exec", "nohup", "time", "sudo", "doas"):
                continue
            if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tok):
                continue
            if tok.startswith("-"):
                continue
            skipping_prefix = False
        clean.append(tok.lstrip("\\"))

    if not clean:
        continue

    head = clean[0]
    if head not in READ_VERBS:
        continue

    # `cat $(command -v gitcommit)` never yields a literal path token — the
    # args tokenize as `$(command`, `-v`, `gitcommit)`, so the per-arg check
    # below sees no gitcommit path and the read goes through. Match the
    # resolver substitution itself against the raw sub-command instead.
    # Scoped to a read verb, so `gitcommit --dir $(pwd) all` is untouched.
    if RESOLVER_SUBST_RE.search(sub_cmd):
        print(msg)
        sys.stderr.write(msg + "\n")
        sys.exit(2)

    for arg in clean[1:]:
        if arg.startswith("-"):
            continue
        if is_gitcommit_path(arg):
            print(msg)
            sys.stderr.write(msg + "\n")
            sys.exit(2)

sys.exit(0)
PYEOF

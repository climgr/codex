#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202610070001-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  drift-guard-read.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Friday, May 16, 2026 00:00 EDT
# @@File             :  drift-guard-read.sh
# @@Description      :  PreToolUse Read+Bash hook: block reading ~/.codex/ deployed copies when a home/ source exists
# @@Changelog        :  20261007: Scan shell -c commands behind common wrappers.
# @@TODO             :
# @@Other            :  Fires only when inside a climgr/codex project (detected by presence of home/AGENTS.md); fails open if the home/ source doesn't exist; DRIFT_GUARD_ALLOW=1 <cmd> bypasses the block for that one Bash call
# @@Resource         :  home/hooks/no-read-gitcommit.sh
# - - - - - - - - - - - - - - - - - - - - - - - - -
VERSION="202610070003-git"
# - - - - - - - - - - - - - - - - - - - - - - - - -

set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  printf 'drift-guard-read.sh: python3 not found — drift guard disabled\n' >&2
  exit 0
fi

DRIFT_GUARD_READ_INPUT="$(cat)"

DRIFT_GUARD_READ_INPUT_TMPFILE="$(mktemp)"
trap 'rm -f "$DRIFT_GUARD_READ_INPUT_TMPFILE"' EXIT
printf '%s' "$DRIFT_GUARD_READ_INPUT" > "$DRIFT_GUARD_READ_INPUT_TMPFILE"

python3 - "$DRIFT_GUARD_READ_INPUT_TMPFILE" <<'PYEOF'
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
if tool_name not in ("Read", "Bash"):
    sys.exit(0)

home = os.environ.get("HOME", "")
if not home:
    sys.exit(0)

codex_dir = os.path.join(home, ".codex")

# Only paths under ~/.codex/ that have a home/ source equivalent
WATCHED_PREFIXES = (
    os.path.join(codex_dir, "AGENTS.md"),
    os.path.join(codex_dir, "config.toml"),
    os.path.join(codex_dir, "memory") + os.sep,
    os.path.join(codex_dir, "agents") + os.sep,
    os.path.join(codex_dir, "hooks") + os.sep,
    os.path.join(codex_dir, "hooks.json"),
    os.path.join(codex_dir, "apply-patch-policy.py"),
    os.path.join(codex_dir, "codex-read-mark.py"),
    os.path.join(codex_dir, "skills") + os.sep,
    os.path.join(codex_dir, "TEMPLATES") + os.sep,
)


def is_watched(path):
    return path in WATCHED_PREFIXES[:2] or path.startswith(WATCHED_PREFIXES[2:])


def resolve_home(path):
    if not path:
        return ""
    if path == "~":
        return home
    if path.startswith("~/"):
        return home + path[1:]
    return path


def project_root(cwd):
    try:
        import subprocess
        out = subprocess.run(
            ["git", "-C", cwd, "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=5,
        )
        if out.returncode != 0:
            return ""
        return out.stdout.strip()
    except Exception:
        return ""


def check_and_block(path, override):
    path = resolve_home(path)
    if not is_watched(path):
        return
    cwd = payload.get("cwd", "") or os.getcwd()
    proj = project_root(cwd)
    if not proj or not os.path.isfile(os.path.join(proj, "home", "AGENTS.md")):
        return
    relative = path[len(codex_dir) + 1:]
    source = os.path.join(proj, "home", relative)
    # Only redirect when a home/ source actually exists — a deployed-only
    # file (nothing to redirect to) must fail open, not block the read
    if not os.path.exists(source):
        return
    # Explicit per-call override: the user directed this specific read of
    # the deployed copy (e.g. to check the live runtime value), so this is
    # not accidental drift. Only honored via the Bash env-var prefix below,
    # never silently — Codex sets it only when the user's own message asked
    # for the deployed file, per AGENTS.md's "only they decide" rule.
    if override:
        return
    msg = (
        f"BLOCKED: Drift guard — read home/{relative} (source) not "
        f"~/.codex/{relative} (deployed copy).\n"
        f"Source files live in {proj}/home/ and are deployed to ~/.codex/ "
        "by the deploy script.\n"
        "Never read deployed copies from within this project."
    )
    print(msg)
    sys.stderr.write(msg + "\n")
    sys.exit(2)


if tool_name == "Read":
    # The Read tool's schema has no field to carry an explicit-override
    # signal, so the override below only works via Bash. A user-directed
    # read of the deployed copy must go through Bash with the
    # DRIFT_GUARD_ALLOW=1 prefix documented there.
    check_and_block(payload.get("tool_input", {}).get("file_path", "") or "", False)
    sys.exit(0)

# Bash: cat/less/head/etc. reads the same deployed copies but bypasses the
# Read tool entirely, so it needs the same redirect check.
cmd = payload.get("tool_input", {}).get("command", "")
if not cmd:
    sys.exit(0)

READ_VERBS = {"cat", "less", "more", "head", "tail", "vim", "vi", "nano",
              "view", "bat", "sed", "awk", "grep", "rg", "xxd", "od",
              "strings", "nl", "tac", "cut", "wc", "file", ".", "source"}

for sub_cmd in split_shell_commands(cmd):
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
            if tok == "DRIFT_GUARD_ALLOW=1":
                override = True
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

    for arg in clean[1:]:
        if arg.startswith("-"):
            continue
        check_and_block(arg, override)

sys.exit(0)
PYEOF

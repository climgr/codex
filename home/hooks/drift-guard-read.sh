#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202609170001-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  drift-guard-read.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Friday, May 16, 2026 00:00 EDT
# @@File             :  drift-guard-read.sh
# @@Description      :  PreToolUse Read+Bash hook: block reading ~/.codex/ deployed copies when a home/ source exists
# @@Changelog        :  Decode the stdin payload file as UTF-8 with replacement and fail open on any parse exception (not only JSONDecodeError) — a non-UTF-8 byte previously raised UnicodeDecodeError and surfaced as a hook error.
# @@TODO             :
# @@Other            :  Fires only when inside a codexmgr/config project (detected by presence of home/AGENTS.md); fails open if the home/ source doesn't exist; DRIFT_GUARD_ALLOW=1 <cmd> bypasses the block for that one Bash call
# @@Resource         :  home/hooks/no-read-gitcommit.sh
# - - - - - - - - - - - - - - - - - - - - - - - - -
VERSION="202609170001-git"
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

for sub_cmd in re.split(r"[\n;]|&&|\|\||[|&]", cmd):
    sub_cmd = sub_cmd.strip()
    if not sub_cmd:
        continue
    try:
        tokens = shlex.split(sub_cmd)
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

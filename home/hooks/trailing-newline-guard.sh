#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202609170001-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  trailing-newline-guard.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Sunday, August 30, 2026 22:00 EDT
# @@File             :  trailing-newline-guard.sh
# @@Description      :  PostToolUse Write+Edit hook: enforces the trailing-newline rule read-only, blocking with a remediation message instead of rewriting the file.
# @@Changelog        :  Decode the stdin payload file as UTF-8 with replacement and fail open on any parse exception (not only JSONDecodeError) — a non-UTF-8 byte previously raised UnicodeDecodeError and surfaced as a hook error.
# @@TODO             :  None
# @@Other            :  Skips secret/token files, VERSION, lockfiles, binary content, empty files, nonexistent paths; applies everywhere.
# @@Resource         :  file_ending_conventions.md, AGENTS.md - Code & Files
# @@Terminal App     :  no
# @@sudo/root        :  no
# @@Template         :  shell/bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC1001,SC1003,SC2001,SC2003,SC2016,SC2031,SC2090,SC2115,SC2120,SC2155,SC2199,SC2229,SC2317,SC2329
# - - - - - - - - - - - - - - - - - - - - - - - - -
VERSION="202609170001-git"
# - - - - - - - - - - - - - - - - - - - - - - - - -
set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  printf 'trailing-newline-guard.sh: required command not found: python3 (hook disabled, failing open)\n' >&2
  exit 0
fi

TRAILING_NEWLINE_GUARD_INPUT="$(cat)"

TRAILING_NEWLINE_GUARD_INPUT_TMPFILE="$(mktemp)"
trap 'rm -f "$TRAILING_NEWLINE_GUARD_INPUT_TMPFILE"' EXIT
printf '%s' "$TRAILING_NEWLINE_GUARD_INPUT" > "$TRAILING_NEWLINE_GUARD_INPUT_TMPFILE"

python3 - "$TRAILING_NEWLINE_GUARD_INPUT_TMPFILE" <<'PYEOF'
import json
import os
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

if payload.get("tool_name", "") not in ("Write", "Edit"):
    sys.exit(0)

# A non-string file_path (number, null, list) reaches os.path.expanduser
# below and raises TypeError — exit 1, reported as a hook error. Part 6
# requires failing open on any unusable payload instead.
path = payload.get("tool_input", {}).get("file_path", "")
if not isinstance(path, str):
    path = ""
if not path:
    sys.exit(0)
path = os.path.expanduser(path)
if not os.path.isfile(path) or os.path.islink(path):
    sys.exit(0)

EXEMPT_BASENAMES = {"VERSION", ".password", "htpasswd", ".htpasswd"}
EXEMPT_LOCKFILES = {
    "package-lock.json", "yarn.lock", "Cargo.lock", "go.sum",
    "pnpm-lock.yaml", "composer.lock",
}
# .pem/.key/.crt are text (base64/PEM armor), not binary — file_ending_
# conventions.md:12 explicitly requires the trailing newline on PEM keys.
# .der/.p12/.pfx are genuinely binary encodings (DER, PKCS#12) and stay
# exempt; .token stays exempt as a single-value secret file per that same
# doc's Exceptions table.
EXEMPT_EXT = {
    ".token", ".der", ".p12", ".pfx",
    ".png", ".jpg", ".jpeg", ".gif", ".ico", ".webp", ".bmp",
    ".zip", ".tar", ".gz", ".tgz", ".bz2", ".xz", ".7z", ".pdf",
    ".woff", ".woff2", ".ttf", ".eot", ".otf",
    ".so", ".dylib", ".dll", ".exe", ".bin", ".wasm", ".jar", ".class",
    ".mp3", ".mp4", ".mov", ".avi", ".sqlite", ".db", ".lock",
}

basename = os.path.basename(path)
_, ext = os.path.splitext(basename)
if basename in EXEMPT_BASENAMES or basename in EXEMPT_LOCKFILES or ext in EXEMPT_EXT:
    sys.exit(0)

try:
    with open(path, "rb") as f:
        data = f.read()
except OSError:
    sys.exit(0)

if not data:
    sys.exit(0)
if b"\x00" in data[:8000]:
    sys.exit(0)

if data.endswith(b"\n\n"):
    reason = "has blank line(s) at EOF — must end with exactly ONE trailing newline"
elif not data.endswith(b"\n"):
    reason = "is missing its trailing newline"
else:
    sys.exit(0)

msg = (
    f"BLOCKED: trailing-newline-guard — {path} {reason}.\n"
    "file_ending_conventions.md: every text file ends with a single trailing\n"
    "newline. Fix with a small Edit/Write to this file before continuing.\n"
    "Two exceptions this hook cannot auto-detect: a fragment file spliced\n"
    "mid-line into another file, or a filetype where the project's own\n"
    "formatter/linter/generator enforces a different ending — in either\n"
    "case the file is legitimately exempt and this block should be waived\n"
    "by a human, not auto-fixed."
)
print(msg)
sys.stderr.write(msg + "\n")
sys.exit(2)
PYEOF

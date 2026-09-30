#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202609170001-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  comment-placement-guard.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Sunday, August 30, 2026 23:00 EDT
# @@File             :  comment-placement-guard.sh
# @@Description      :  PreToolUse Write+Edit hook: blocks comment syntax in .json files and inline trailing comments in common source files, a previously prose-only rule.
# @@Changelog        :  Decode the stdin payload file as UTF-8 with replacement and fail open on any parse exception (not only JSONDecodeError) — a non-UTF-8 byte previously raised UnicodeDecodeError and surfaced as a hook error.
# @@TODO             :  None
# @@Other            :  String-aware JSON check; narrow extension-list inline check; exempts `# noqa`/`# type: ignore`/`// nolint` and CI SHA-pin annotations.
# @@Resource         :  AGENTS.md - Code & Files, comment_conventions.md
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
  printf 'comment-placement-guard.sh: required command not found: python3 (hook disabled, failing open)\n' >&2
  exit 0
fi

COMMENT_PLACEMENT_GUARD_INPUT="$(cat)"

COMMENT_PLACEMENT_GUARD_INPUT_TMPFILE="$(mktemp)"
trap 'rm -f "$COMMENT_PLACEMENT_GUARD_INPUT_TMPFILE"' EXIT
printf '%s' "$COMMENT_PLACEMENT_GUARD_INPUT" > "$COMMENT_PLACEMENT_GUARD_INPUT_TMPFILE"

python3 - "$COMMENT_PLACEMENT_GUARD_INPUT_TMPFILE" <<'PYEOF'
import json
import os
import re
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
if tool_name not in ("Write", "Edit"):
    sys.exit(0)

tool_input = payload.get("tool_input", {})
file_path = tool_input.get("file_path", "") or ""
content = tool_input.get("content", "") if tool_name == "Write" else tool_input.get("new_string", "")

# file_path and the content field are both attacker/bug-reachable as any JSON
# type. A list file_path reaches os.path.splitext and a numeric content
# reaches .split(), each raising TypeError -> exit 1 -> "hook error" on a
# normal tool call. Part 6 requires failing open on an unusable payload.
if not isinstance(file_path, str):
    file_path = ""
if not isinstance(content, str):
    sys.exit(0)
if not content:
    sys.exit(0)

basename = os.path.basename(file_path)
if basename == "COMMIT_MESS":
    sys.exit(0)

_, ext = os.path.splitext(basename)
findings = []


def line_of(index, text):
    return text.count("\n", 0, index) + 1


if ext == ".json":
    in_string = False
    escape = False
    i = 0
    n = len(content)
    while i < n:
        c = content[i]
        if in_string:
            if escape:
                escape = False
            elif c == "\\":
                escape = True
            elif c == '"':
                in_string = False
            i += 1
            continue
        if c == '"':
            in_string = True
            i += 1
            continue
        if c == "/" and i + 1 < n and content[i + 1] in ("/", "*"):
            snippet = content[i:i + 40].split("\n", 1)[0]
            findings.append(f"line {line_of(i, content)}: comment in JSON: {snippet[:80]}")
            i += 2
            continue
        i += 1

    if findings:
        lines = ["BLOCKED: comment syntax found in a .json file.\n"]
        for f in findings[:20]:
            lines.append(f"  - {f}")
        lines.append("")
        lines.append(
            "comment_conventions.md: JSON has no comment syntax - comments break\n"
            "parsers and validators. Use a separate doc file instead."
        )
        msg = "\n".join(lines)
        print(msg)
        sys.stderr.write(msg + "\n")
        sys.exit(2)
    sys.exit(0)

ENV_BASENAMES = {".env", "app.env", "default.env"}
NO_COMMENT_EXT = {".csv", ".tsv"}

if basename in ENV_BASENAMES or ext in NO_COMMENT_EXT:
    kind = "KEY=VALUE" if basename in ENV_BASENAMES else "CSV/TSV"
    for lineno, line in enumerate(content.split("\n"), start=1):
        stripped = line.lstrip()
        if stripped.startswith("#"):
            findings.append(f"line {lineno}: comment line in a {kind} file: {stripped[:80]}")

    if findings:
        lines = [f"BLOCKED: comment syntax found in a {kind} file.\n"]
        for f in findings[:20]:
            lines.append(f"  - {f}")
        lines.append("")
        lines.append(
            "comment_conventions.md: .env/app.env/default.env KEY=VALUE files and\n"
            "CSV/TSV are pure data formats — comments are never valid there, even\n"
            "though some parsers tolerate a leading '#'. Remove the comment line."
        )
        msg = "\n".join(lines)
        print(msg)
        sys.stderr.write(msg + "\n")
        sys.exit(2)
    sys.exit(0)

HASH_COMMENT_EXT = {".sh", ".bash", ".py", ".rb", ".yml", ".yaml", ".toml", ".ini"}
SLASH_COMMENT_EXT = {
    ".go", ".rs", ".js", ".jsx", ".ts", ".tsx",
    ".java", ".c", ".cpp", ".cc", ".h", ".hpp",
}

if ext not in HASH_COMMENT_EXT and ext not in SLASH_COMMENT_EXT:
    sys.exit(0)

INLINE_EXEMPT_RE = re.compile(r"#\s*(noqa|type:\s*ignore)\b|//\s*nolint\b", re.IGNORECASE)
# comment_conventions.md's SHA-pin exemption covers "CI workflow" annotations
# generically, not GitHub specifically — Gitea and Forgejo use the same
# `uses: owner/action@{sha}  # vX.Y.Z` Action syntax under their own
# workflow directories, so both need the same exemption GitHub gets.
WORKFLOW_DIRS = (".github/workflows/", ".gitea/workflows/", ".forgejo/workflows/")
NORMALIZED_PATH = file_path.replace(os.sep, "/")
IS_WORKFLOW = any(d in NORMALIZED_PATH for d in WORKFLOW_DIRS) and ext in (".yml", ".yaml")
SHA_PIN_RE = re.compile(r"^\s*(-\s*)?uses:\s*\S+@[0-9a-f]{40}\s*#\s*v\S+\s*$")

MAX_COMMENT_LEN = 180

# The `##@Version` / `# @@Field : value` script header is a fixed template
# where each field is exactly one line — a long `@@Changelog`, `@@Other`,
# `@@Description` or `@@Resource` value cannot be wrapped without breaking
# the format the template parses. Applying the prose 180-char limit to it
# blocked editing any script whose header carried a detailed changelog,
# so header field lines are exempt from the length check only.
HEADER_FIELD_RE = re.compile(r"^\s*(?:#{1,2}|//)\s*@{1,2}[A-Za-z][\w ]*:")


def find_unquoted_marker(line, marker):
    """Return the index of the first unquoted comment marker on the line,
    tracking single/double-quote state so a '#' or '//' inside a string
    literal is never mistaken for a comment start. Returns -1 if none."""
    in_squote = False
    in_dquote = False
    i = 0
    n = len(line)
    while i < n:
        c = line[i]
        if in_squote:
            if c == "\\":
                i += 2
                continue
            if c == "'":
                in_squote = False
            i += 1
            continue
        if in_dquote:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                in_dquote = False
            i += 1
            continue
        if c == "'":
            in_squote = True
            i += 1
            continue
        if c == '"':
            in_dquote = True
            i += 1
            continue
        if marker == "#":
            if c == "#" and not (i + 1 < n and line[i + 1] == "!"):
                return i
        elif c == "/" and i + 1 < n and line[i + 1] == "/":
            return i
        i += 1
    return -1


for lineno, line in enumerate(content.split("\n"), start=1):
    stripped = line.lstrip()
    if not stripped:
        continue
    if stripped.startswith("#") or stripped.startswith("//"):
        if len(line) > MAX_COMMENT_LEN and not HEADER_FIELD_RE.match(line):
            findings.append(f"line {lineno}: comment exceeds {MAX_COMMENT_LEN} chars ({len(line)}): {line.strip()[:80]}...")
        continue

    marker = "#" if ext in HASH_COMMENT_EXT else "//" if ext in SLASH_COMMENT_EXT else None
    if marker is None:
        continue
    idx = find_unquoted_marker(line, marker)
    if idx < 1 or line[idx - 1] not in (" ", "\t"):
        continue

    comment_text = line[idx:]
    if INLINE_EXEMPT_RE.search(comment_text):
        continue
    if IS_WORKFLOW and SHA_PIN_RE.match(line):
        continue
    findings.append(f"line {lineno}: inline comment (must be on its own line above): {line.strip()[:80]}")

if not findings:
    sys.exit(0)

lines = ["BLOCKED: comment placement/length violation detected.\n"]
for f in findings[:20]:
    lines.append(f"  - {f}")
lines.append("")
lines.append(
    "comment_conventions.md: comments always go ABOVE the code they describe,\n"
    "never appended to the end of a code line, and must be a single line of\n"
    f"{MAX_COMMENT_LEN} characters or fewer. Move an inline comment to its own\n"
    "line above (or use a documented exception: # noqa, # type: ignore,\n"
    "// nolint, a CI workflow SHA-pin annotation), or split/shorten an\n"
    "over-length comment."
)
msg = "\n".join(lines)
print(msg)
sys.stderr.write(msg + "\n")
sys.exit(2)
PYEOF

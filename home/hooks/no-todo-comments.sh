#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202609170001-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  no-todo-comments.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Sunday, August 30, 2026 21:00 EDT
# @@File             :  no-todo-comments.sh
# @@Description      :  PreToolUse Write+Edit hook: blocks TODO/FIXME/HACK markers and a narrow commented-out-code heuristic, enforcing previously prose-only AGENTS.md rules.
# @@Changelog        :  Decode the stdin payload file as UTF-8 with replacement and fail open on any parse exception (not only JSONDecodeError) — a non-UTF-8 byte previously raised UnicodeDecodeError and surfaced as a hook error.
# @@TODO             :  None
# @@Other            :  Never matches `# @@TODO : None` or mid-sentence mentions; TODO.AI.md/TODO.md/PLAN.AI.md/PLAN.md are exempt; commented-code detection is conservative.
# @@Resource         :  AGENTS.md - Code & Files
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
  printf 'no-todo-comments.sh: required command not found: python3 (hook disabled, failing open)\n' >&2
  exit 0
fi

NO_TODO_COMMENTS_INPUT="$(cat)"

NO_TODO_COMMENTS_INPUT_TMPFILE="$(mktemp)"
trap 'rm -f "$NO_TODO_COMMENTS_INPUT_TMPFILE"' EXIT
printf '%s' "$NO_TODO_COMMENTS_INPUT" > "$NO_TODO_COMMENTS_INPUT_TMPFILE"

python3 - "$NO_TODO_COMMENTS_INPUT_TMPFILE" <<'PYEOF'
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

EXEMPT_BASENAMES = {"TODO.AI.md", "TODO.md", "PLAN.AI.md", "PLAN.md", "AUDIT.AI.md", "COMMIT_MESS"}
if os.path.basename(file_path) in EXEMPT_BASENAMES:
    sys.exit(0)

# Comment syntax is per-language, so the leader set is chosen by extension.
# Accepting every leader for every file made `--flag=value` continuation
# lines inside a shell string parse as commented-out SQL, since `--` only
# starts a comment in SQL/Lua/Haskell, never in a shell script.
ext = os.path.splitext(file_path)[1].lower()
HASH_EXTS = {".sh", ".bash", ".zsh", ".fish", ".py", ".rb", ".pl", ".yml",
             ".yaml", ".toml", ".cfg", ".conf", ".tf", ".mk", ".r", ".jl"}
SLASH_EXTS = {".c", ".h", ".cc", ".cpp", ".hpp", ".go", ".rs", ".java", ".js",
              ".jsx", ".ts", ".tsx", ".mjs", ".cjs", ".cs", ".kt", ".kts",
              ".swift", ".php", ".scala", ".dart", ".proto", ".css", ".scss"}
DASH_EXTS = {".sql", ".lua", ".hs", ".adb", ".ads", ".elm"}
SEMI_EXTS = {".ini", ".lisp", ".el", ".clj", ".asm", ".s"}

# Markdown uses `#` for headings and `*`/`-` for list bullets, not comment
# syntax — the only real comment form it has is an HTML `<!--` block. Using
# the full code-comment prefix set here false-positived a Markdown "# TODO"
# heading as a marker and a "* key = value" bullet as commented-out code.
is_markdown = ext == ".md"
if is_markdown:
    leaders = [r"<!--"]
elif ext in HASH_EXTS:
    leaders = [r"#"]
elif ext in SLASH_EXTS:
    leaders = [r"//", r"/\*", r"\*"]
elif ext in DASH_EXTS:
    leaders = [r"--"]
elif ext in SEMI_EXTS:
    leaders = [r";", r"#"]
else:
    leaders = [r"#", r"//", r"/\*", r"\*", r"--", r";", r"<!--"]
COMMENT_PREFIX = r"^\s*(?:" + r"|".join(leaders) + r")\s*"

MARKER_RE = re.compile(
    COMMENT_PREFIX + r"(TODO|FIXME|HACK)\b",
)

# Every alternative below requires code PUNCTUATION, not just a keyword.
# `for`, `return`, `private`, `class` and `from` all begin ordinary English
# comment prose ("for the exemption check", "private keys / certificates"),
# and a bare `word=value` appears in any comment naming a flag, so the old
# keyword-or-assignment shapes blocked normal documentation.
# An assignment or a `return` counts only when the line ends in a statement
# terminator, and a call counts only with arguments or a trailing `;`/`{` —
# that keeps `# __extract_content()` (a cross-reference) out of the net.
CODE_SHAPE_RE = re.compile(
    COMMENT_PREFIX + r"(?:"
    r"(?:import|from)\s+[A-Za-z_][\w.]*(?:\s+import\s+[\w.,*\s]+)?\s*;?\s*$"
    r"|(?:def|class|func|fn|function)\s+[A-Za-z_]\w*\s*[(:{]"
    r"|(?:if|for|while|switch|catch|elif|foreach)\s*\("
    r"|(?:return|throw|yield)\b[^;]*;\s*$"
    r"|(?:var|let|const)\s+[A-Za-z_]\w*\s*[=:;]"
    r"|(?:public|private|protected|static)\s+[\w<>\[\].]+\s+[A-Za-z_]\w*\s*[=;(]"
    r"|(?:else|try|finally|do)\s*\{\s*$"
    r"|(?:module\.exports|self\.\w+)\s*=\s*[^=\s]"
    r"|[A-Za-z_][\w.]*\s*[-+*/|&^]?=\s*[^=\s][^;]*;\s*$"
    r"|[A-Za-z_][\w.]*\((?:[^()]+\)\s*[;{]?|\)\s*[;{])\s*$"
    r")"
)

findings = []
for lineno, line in enumerate(content.split("\n"), start=1):
    m = MARKER_RE.match(line)
    if m:
        findings.append(f"line {lineno}: {m.group(1)} marker: {line.strip()[:80]}")
        continue
    # Commented-out-code detection is meaningless for Markdown — `*`/`-`
    # bullets and `key = value`-shaped prose lines are normal there, not code.
    if not is_markdown and CODE_SHAPE_RE.match(line):
        findings.append(f"line {lineno}: looks like commented-out code: {line.strip()[:80]}")

if not findings:
    sys.exit(0)

lines = ["BLOCKED: TODO/FIXME/HACK marker or commented-out code detected.\n"]
for f in findings[:20]:
    lines.append(f"  - {f}")
lines.append("")
lines.append(
    "AGENTS.md: \"No TODO/FIXME/HACK in committed code\" and \"No commented-out\n"
    "code\". Finish the work now, or track it in TODO.AI.md instead."
)
msg = "\n".join(lines)
print(msg)
sys.stderr.write(msg + "\n")
sys.exit(2)
PYEOF

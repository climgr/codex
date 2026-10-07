#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202610070001-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  enforce-test-lint-gate.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Sunday, August 30, 2026 22:00 EDT
# @@File             :  enforce-test-lint-gate.sh
# @@Description      :  PreToolUse Bash hook: requires primary-session test/lint gate markers before the commit wrapper runs.
# @@Changelog        :  20261007: Scan shell -c commands behind common wrappers.
# @@TODO             :  None
# @@Other            :  Pairs with test-lint-mark.sh. TEST_LINT_GATE_OVERRIDE=1 <gitcommit ...> bypasses the gate for that one call — user-directed only, never Codex's own initiative.
# @@Resource         :  AGENTS.md - Commit Workflow, home/hooks/test-lint-mark.sh, home/hooks/spec-guard.sh
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
  printf 'enforce-test-lint-gate.sh: required command not found: python3 (hook disabled, failing open)\n' >&2
  exit 0
fi

# $(cat) is required here — hook stdin is a socket; $(</dev/stdin) re-opens it and fails with ENXIO
ENFORCE_TEST_LINT_GATE_INPUT="$(cat)"

ENFORCE_TEST_LINT_GATE_INPUT_TMPFILE="$(mktemp)"
trap 'rm -f "$ENFORCE_TEST_LINT_GATE_INPUT_TMPFILE"' EXIT
printf '%s' "$ENFORCE_TEST_LINT_GATE_INPUT" > "$ENFORCE_TEST_LINT_GATE_INPUT_TMPFILE"

python3 - "$ENFORCE_TEST_LINT_GATE_INPUT_TMPFILE" <<'PYEOF'
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

if payload.get("tool_name", "") != "Bash":
    sys.exit(0)

cmd = payload.get("tool_input", {}).get("command", "")
session_id = payload.get("session_id", "")
if not cmd or not session_id or not re.search(r"\bgitcommit\b", cmd):
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
                if tok == "TEST_LINT_GATE_OVERRIDE=1":
                    override = True
                    continue
                if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tok):
                    continue
                if tok.startswith("-"):
                    continue
                skipping_prefix = False
            clean.append(tok.lstrip("\\"))

        if len(clean) == 4 and clean[0] == "gitcommit" and clean[1] == "--dir" and clean[3] == "all":
            yield clean[2], override


targets = list(find_gitcommit_dir(cmd))
if not targets:
    sys.exit(0)

# TEST_LINT_GATE_OVERRIDE=1 <gitcommit ...> is an explicit, per-invocation,
# user-directed bypass. Codex sets this prefix only when the user's own
# message explicitly says to bypass/skip the gate after confirming they
# already verified the test/lint run passed — never on its own initiative
# just because the gate blocked (AGENTS.md: "never auto-bypass a hook").
# Same prefix pattern as drift-guard-read.sh's DRIFT_GUARD_ALLOW=1.
if any(override for _target, override in targets):
    sys.exit(0)

targets = [target for target, _override in targets]

# Must match the deterministic path test-lint-mark.sh writes (see its
# comments for why this deviates from
# tempdir_conventions.md's -XXXXXX mktemp-suffix pattern: session_id is
# the lookup key here, so it takes the uniqueness role -XXXXXX would).
#
# `or "/tmp"` rather than a get() default: the writers use bash's
# ${TMPDIR:-/tmp}, which also falls back when TMPDIR is set but EMPTY.
# os.environ.get("TMPDIR", "/tmp") returns "" in that case, making these
# paths relative to the cwd — the reader would then never find markers the
# writers put in /tmp, permanently false-blocking every gitcommit.
tmp_root = os.environ.get("TMPDIR") or "/tmp"
marker_dir = os.path.join(tmp_root, "codex-hooks", "test-lint-guard", session_id)
spec_guard_marker = os.path.join(tmp_root, "codex-hooks", "spec-guard", session_id, "read")


def marked(marker_file, project):
    try:
        with open(marker_file) as f:
            return any(line.rstrip("\n") == project for line in f)
    except OSError:
        return False


# PostToolUse does not expose a reliable command exit status, and Codex states
# transcript_path is not a stable hook interface. Test markers therefore come
# only from test-lint-mark.sh after test-lint-run.sh emits its success sentinel;
# Lint markers come from successful primary-session commands through the runner.
def has_shell_scripts(root):
    # project_type_conventions.md's spec-collection rule scans "anywhere in
    # its tree", unqualified — no depth limit. A bare deploy-only install.sh
    # at the project root does not disqualify spec-collection on its own;
    # any *.sh/*.bash file elsewhere in the tree does.
    skip = {".git", "node_modules", "vendor", ".venv", "target", "dist", "build"}
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in skip]
        for f in filenames:
            if not f.endswith((".sh", ".bash")):
                continue
            if dirpath == root and f == "install.sh":
                continue
            return True
    return False


# Authoritative manifest set from project_type_conventions.md's
# script-collection/spec-collection detection signals — one fixed
# filename per language/build-system, each with a documented test/lint
# gate command and its own
# ~/.codex/memory/{lang}_conventions.md reference file (home/AGENTS.md's
# Language Constraints section). dotnet's *.csproj/*.sln are not fixed
# filenames, so they use the has_dotnet_manifest() glob check instead.
MANIFESTS = (
    "go.mod", "Cargo.toml", "package.json", "pyproject.toml",
    "build.gradle", "build.gradle.kts", "pom.xml",
    "Gemfile", "composer.json", "Package.swift", "pubspec.yaml",
    "CMakeLists.txt", "mix.exs",
)


def has_dotnet_manifest(root):
    try:
        return any(f.endswith((".csproj", ".sln")) for f in os.listdir(root))
    except OSError:
        return False


def has_any_manifest(root):
    return (
        any(os.path.isfile(os.path.join(root, m)) for m in MANIFESTS)
        or has_dotnet_manifest(root)
    )


def is_spec_collection(root):
    if has_any_manifest(root):
        return False
    return not has_shell_scripts(root)


blocked = []
for target in targets:
    project = os.path.realpath(os.path.expanduser(target))
    if not os.path.isdir(project):
        continue

    if is_spec_collection(project):
        if not marked(spec_guard_marker, project):
            blocked.append(
                f"{project}: spec-collection project — AI.md/SPEC.md (or, for a template repo with "
                f"neither, its root-level *.md spec file) has not been re-read this session "
                f"(AGENTS.md's substitute for a test runner here)."
            )
        continue

    manifests_present = has_any_manifest(project)
    missing = []
    if not marked(os.path.join(marker_dir, "test"), project):
        missing.append("test gate")
    # Every manifest language has a documented lint gate — direct primary-
    # session commands such as shellcheck, go vet/golangci-lint, cargo clippy,
    # `npm run lint` for Node/TS
    # (node_typescript_conventions.md), `ruff check` + `ruff format --check`
    # for Python (python_conventions.md), and the documented direct lint
    # commands for every other manifest language — so any manifest
    # or shell script in the tree means the lint gate is both defined and
    # satisfiable.
    has_defined_lint_target = manifests_present or has_shell_scripts(project)
    if (
        has_defined_lint_target
        and not marked(os.path.join(marker_dir, "lint"), project)
    ):
        missing.append("lint gate")
    if missing:
        blocked.append(f"{project}: {' and '.join(missing)} has not run (and passed) this session")

if not blocked:
    sys.exit(0)

msg_lines = ["BLOCKED: gitcommit requires the test/lint gate to have run and passed this session.\n"]
for b in blocked:
    msg_lines.append(f"  - {b}")
msg_lines.append("")
msg_lines.append(
    "Run test and direct lint commands through `bash \"$HOME/.codex/hooks/test-lint-run.sh\" {test|lint|both} -- <command>` "
    "so the PostToolUse hook can verify the actual exit status.\n"
    "Run the project's direct lint command in the primary session through `bash \"$HOME/.codex/hooks/test-lint-run.sh\" lint -- <command>`, then retry the commit."
)
msg = "\n".join(msg_lines)
print(msg)
sys.stderr.write(msg + "\n")
sys.exit(2)
PYEOF

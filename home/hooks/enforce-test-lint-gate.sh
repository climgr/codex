#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202610020003-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  enforce-test-lint-gate.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Sunday, August 30, 2026 22:00 EDT
# @@File             :  enforce-test-lint-gate.sh
# @@Description      :  PreToolUse Bash hook: requires explicit Codex gate-result markers before the commit wrapper runs.
# @@Changelog        :  20261002: Remove unsupported transcript success inference; require exit-status sentinels from test-lint-run.sh.
# @@TODO             :  None
# @@Other            :  Pairs with test-lint-mark.sh and lint-agent-mark.sh. TEST_LINT_GATE_OVERRIDE=1 <gitcommit ...> bypasses the gate for that one call — user-directed only, never Codex's own initiative.
# @@Resource         :  AGENTS.md - Commit Workflow, home/hooks/test-lint-mark.sh, home/hooks/spec-guard.sh
# @@Terminal App     :  no
# @@sudo/root        :  no
# @@Template         :  shell/bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC1001,SC1003,SC2001,SC2003,SC2016,SC2031,SC2090,SC2115,SC2120,SC2155,SC2199,SC2229,SC2317,SC2329
# - - - - - - - - - - - - - - - - - - - - - - - - -
VERSION="202610020003-git"
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
    for sub_cmd in re.split(r"[\n;]|&&|\|\||[|&]", text):
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

# Must match the deterministic path test-lint-mark.sh/lint-agent-mark.sh
# write (see those files' comments for why this deviates from
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
# lint markers come from lint-agent-mark.sh or a successful wrapped lint command.
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
    # Every manifest language has a documented lint gate — go_lint/rust_lint/
    # script_lint agents for Go/Rust/shell, `npm run lint` for Node/TS
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
    "Run script_lint/go_lint/rust_lint through the Agent tool; a clean SubagentStop result records its lint marker. Then retry gitcommit."
)
msg = "\n".join(msg_lines)
print(msg)
sys.stderr.write(msg + "\n")
sys.exit(2)
PYEOF

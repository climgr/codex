#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202610070001-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  test-lint-mark.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Sunday, August 30, 2026 22:00 EDT
# @@File             :  test-lint-mark.sh
# @@Description      :  PostToolUse Bash hook: records test/lint success only from the explicit test-lint-run.sh result marker.
# @@Changelog        :  20261007: Accept direct primary-session shell, Go, and Rust lint results.
# @@TODO             :  None
# @@Other            :  Codex PostToolUse runs on failed commands and exposes no exit code; only test-lint-run.sh's PASS sentinel can satisfy this gate.
# @@Resource         :  AGENTS.md - Commit Workflow (Test gate, Lint gate), home/hooks/spec-guard-mark.sh
# @@Terminal App     :  no
# @@sudo/root        :  no
# @@Template         :  shell/bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC1001,SC1003,SC2001,SC2003,SC2016,SC2031,SC2090,SC2115,SC2120,SC2155,SC2199,SC2229,SC2317,SC2329
# - - - - - - - - - - - - - - - - - - - - - - - - -
VERSION="202610070001-git"
# - - - - - - - - - - - - - - - - - - - - - - - - -
set -euo pipefail

# Fail open when jq is missing — a broken hook must never crash the tool run
if ! command -v jq >/dev/null 2>&1; then
  printf 'test-lint-mark.sh: jq not found — test/lint mark disabled\n' >&2
  exit 0
fi

# $(cat) is required here — hook stdin is a socket; $(</dev/stdin) re-opens it and fails with ENXIO
TEST_LINT_MARK_INPUT="$(cat)"

# Fail open on an empty, malformed, or non-object payload. Without this, jq
# exits 4/5 and `set -e` propagates that code, which Codex surfaces as a
# "hook error" instead of the silent no-op Part 6 requires on a parse failure.
if ! printf '%s' "$TEST_LINT_MARK_INPUT" | jq -e 'type == "object"' >/dev/null 2>&1; then
  exit 0
fi

TEST_LINT_MARK_TOOL=$(printf '%s' "$TEST_LINT_MARK_INPUT" | jq -r 'try (.tool_name) catch "" // ""')
[ "$TEST_LINT_MARK_TOOL" = "Bash" ] || exit 0

TEST_LINT_MARK_CMD=$(printf '%s' "$TEST_LINT_MARK_INPUT" | jq -r 'try (.tool_input.command) catch "" // ""')
TEST_LINT_MARK_CWD=$(printf '%s' "$TEST_LINT_MARK_INPUT" | jq -r 'try (.cwd) catch "" // ""')
TEST_LINT_MARK_SESSION_ID=$(printf '%s' "$TEST_LINT_MARK_INPUT" | jq -r 'try (.session_id) catch "" // ""')
TEST_LINT_MARK_RESPONSE=$(printf '%s' "$TEST_LINT_MARK_INPUT" | jq -r '
  def response_text:
    if type == "string" then .
    elif type == "array" then map(response_text) | join("\n")
    elif type == "object" then
      [(.text? // empty), (.stdout? // empty), (.output? // empty),
       (.content? // empty), (.result? // empty)]
      | map(response_text) | join("\n")
    else "" end;
  try (.tool_response | response_text) catch ""
')
[ -z "$TEST_LINT_MARK_CMD" ] && exit 0
[ -z "$TEST_LINT_MARK_SESSION_ID" ] && exit 0

# Codex PostToolUse fires for successful and failed commands and documents
# tool_response as a generic JSON value. Extract text without interpreting the
# structure as success, then require the runner's exact leading sentinel.
TEST_LINT_MARK_RESULT=$(printf '%s\n' "$TEST_LINT_MARK_RESPONSE" | sed -n '1p')
case "$TEST_LINT_MARK_RESULT" in
  CODEX_TEST_LINT_GATE_V1:PASS:test) TEST_LINT_MARK_RESULT_KIND="test" ;;
  CODEX_TEST_LINT_GATE_V1:PASS:lint) TEST_LINT_MARK_RESULT_KIND="lint" ;;
  CODEX_TEST_LINT_GATE_V1:PASS:both) TEST_LINT_MARK_RESULT_KIND="both" ;;
  *) exit 0 ;;
esac
printf '%s' "$TEST_LINT_MARK_CMD" \
  | grep -qE -- "test-lint-run\\.sh\\\"?[[:space:]]+${TEST_LINT_MARK_RESULT_KIND}[[:space:]]+--" \
  || exit 0

TEST_LINT_MARK_IS_TEST=0
TEST_LINT_MARK_IS_LINT=0
TEST_LINT_MARK_IS_BASHN=0
TEST_LINT_MARK_TEST_RE='\bmake[[:space:]]+test\b|\bgo[[:space:]]+test\b|\bjq[[:space:]]+empty\b'
TEST_LINT_MARK_TEST_RE="${TEST_LINT_MARK_TEST_RE}|\bcargo[[:space:]]+test\b|\bpytest\b"
TEST_LINT_MARK_TEST_RE="${TEST_LINT_MARK_TEST_RE}|\bnpm[[:space:]]+(run[[:space:]]+)?test\b"
TEST_LINT_MARK_TEST_RE="${TEST_LINT_MARK_TEST_RE}|\bmake[[:space:]]+check\b"
# Must stay in sync with enforce-test-lint-gate.sh's TEST_CMD_RE.
TEST_LINT_MARK_TEST_RE="${TEST_LINT_MARK_TEST_RE}|\bgradle[[:space:]]+test\b|\./gradlew[[:space:]]+test\b|\bmvn[[:space:]]+test\b"
TEST_LINT_MARK_TEST_RE="${TEST_LINT_MARK_TEST_RE}|\brspec\b|\bbundle[[:space:]]+exec[[:space:]]+rspec\b|\brake[[:space:]]+test\b"
TEST_LINT_MARK_TEST_RE="${TEST_LINT_MARK_TEST_RE}|\bphpunit\b|\bcomposer[[:space:]]+test\b"
TEST_LINT_MARK_TEST_RE="${TEST_LINT_MARK_TEST_RE}|\bswift[[:space:]]+test\b"
TEST_LINT_MARK_TEST_RE="${TEST_LINT_MARK_TEST_RE}|\bflutter[[:space:]]+test\b|\bdart[[:space:]]+test\b"
TEST_LINT_MARK_TEST_RE="${TEST_LINT_MARK_TEST_RE}|\bctest\b|\bdotnet[[:space:]]+test\b|\bmix[[:space:]]+test\b"
printf '%s' "$TEST_LINT_MARK_CMD" | grep -qE -- "$TEST_LINT_MARK_TEST_RE" \
  && TEST_LINT_MARK_IS_TEST=1
printf '%s' "$TEST_LINT_MARK_CMD" | grep -qE -- '\b(bash|sh)[[:space:]]+-n\b' \
  && TEST_LINT_MARK_IS_BASHN=1
# Lint gates: script-lint/go-lint/rust-lint agents (shell/Go/Rust), `npm run
# lint` (node_typescript_conventions.md's Node/TS gate, `npx eslint` as its
# direct form), `ruff check` / `ruff format --check` (python_conventions.md's
# Python gate), `make check` (climgr/android's APPLICATION.md gate —
# compile + ktlint/detekt lint + JVM unit tests in one Docker-run command;
# ktlint/detekt are never invoked directly on the host, so there is no
# separate bare-tool pattern to match), and the packaging-type per-format
# linters (project_type_conventions.md's Format matrix). Must stay in sync
# with enforce-test-lint-gate.sh's LINT_CMD_RE.
TEST_LINT_MARK_LINT_RE='\bshellcheck\b|\bgolangci-lint[[:space:]]+run\b|\bgo[[:space:]]+vet\b|\bcargo[[:space:]]+clippy\b'
TEST_LINT_MARK_LINT_RE="${TEST_LINT_MARK_LINT_RE}|\bnpm[[:space:]]+run[[:space:]]+lint\b|\bnpx[[:space:]]+eslint\b"
TEST_LINT_MARK_LINT_RE="${TEST_LINT_MARK_LINT_RE}|\bruff[[:space:]]+check\b|\bruff[[:space:]]+format[[:space:]]+--check\b"
TEST_LINT_MARK_LINT_RE="${TEST_LINT_MARK_LINT_RE}|\bmake[[:space:]]+check\b"
TEST_LINT_MARK_LINT_RE="${TEST_LINT_MARK_LINT_RE}|\btaplo[[:space:]]+lint\b"
TEST_LINT_MARK_LINT_RE="${TEST_LINT_MARK_LINT_RE}|\blintian\b|\brpmlint\b|\bnamcap\b|\bapkbuild-lint\b"
TEST_LINT_MARK_LINT_RE="${TEST_LINT_MARK_LINT_RE}|\bbrew[[:space:]]+(audit|style)\b|\bsnapcraft[[:space:]]+lint\b"
TEST_LINT_MARK_LINT_RE="${TEST_LINT_MARK_LINT_RE}|\bflatpak-builder-lint\b|\bappimagelint\b|\bnix[[:space:]]+flake[[:space:]]+check\b|\bstatix\b"
# Kotlin/Gradle, Java/Maven, Ruby, PHP, Swift, Dart/Flutter, C/C++,
# .NET, Elixir — must stay in sync with enforce-test-lint-gate.sh's
# LINT_CMD_RE, and each has its own ~/.codex/memory/{lang}_conventions.md.
TEST_LINT_MARK_LINT_RE="${TEST_LINT_MARK_LINT_RE}|\bgradle[[:space:]]+(lint|ktlintCheck|detekt)\b|\./gradlew[[:space:]]+(lint|ktlintCheck|detekt)\b"
TEST_LINT_MARK_LINT_RE="${TEST_LINT_MARK_LINT_RE}|\bmvn[[:space:]]+checkstyle:check\b|\bmvn[[:space:]]+spotbugs:check\b"
TEST_LINT_MARK_LINT_RE="${TEST_LINT_MARK_LINT_RE}|\brubocop\b|\bphpcs\b|\bphp-cs-fixer\b|\bphpstan\b|\bswiftlint\b"
TEST_LINT_MARK_LINT_RE="${TEST_LINT_MARK_LINT_RE}|\bflutter[[:space:]]+analyze\b|\bdart[[:space:]]+analyze\b"
TEST_LINT_MARK_LINT_RE="${TEST_LINT_MARK_LINT_RE}|\bclang-tidy\b|\bcppcheck\b"
TEST_LINT_MARK_LINT_RE="${TEST_LINT_MARK_LINT_RE}|\bdotnet[[:space:]]+format[[:space:]]+--verify-no-changes\b"
TEST_LINT_MARK_LINT_RE="${TEST_LINT_MARK_LINT_RE}|\bmix[[:space:]]+credo\b|\bmix[[:space:]]+format[[:space:]]+--check-formatted\b"
printf '%s' "$TEST_LINT_MARK_CMD" | grep -qE -- "$TEST_LINT_MARK_LINT_RE" \
  && TEST_LINT_MARK_IS_LINT=1

[ "$TEST_LINT_MARK_IS_TEST" = "1" ] || [ "$TEST_LINT_MARK_IS_BASHN" = "1" ] || [ "$TEST_LINT_MARK_IS_LINT" = "1" ] || exit 0

TEST_LINT_MARK_PROJECT=$(git -C "${TEST_LINT_MARK_CWD:-.}" rev-parse --show-toplevel 2>/dev/null) \
  || TEST_LINT_MARK_PROJECT="$TEST_LINT_MARK_CWD"
[ -z "$TEST_LINT_MARK_PROJECT" ] && exit 0
# Normalize the same way enforce-test-lint-gate.sh's reader normalizes its
# --dir lookup key (Python os.path.realpath) — without this, a marker
# written under a symlinked/un-normalized path never matches the reader's
# realpath'd key and the gate falsely reports the test/lint gate as unrun.
TEST_LINT_MARK_PROJECT=$(realpath -- "$TEST_LINT_MARK_PROJECT" 2>/dev/null) || :

# `bash -n` only satisfies the test gate for script-collection projects
# (home/AGENTS.md's Test gate line) — a project with a real test runner
# (project_type_conventions.md's authoritative manifest set) must not have
# its test gate satisfied by syntax-checking an unrelated script. Must stay
# in sync with enforce-test-lint-gate.sh's MANIFESTS tuple.
if [ "$TEST_LINT_MARK_IS_BASHN" = "1" ] && [ "$TEST_LINT_MARK_IS_TEST" != "1" ]; then
  TEST_LINT_MARK_IS_SCRIPT_COLLECTION=1
  for TEST_LINT_MARK_MANIFEST in \
    go.mod Cargo.toml package.json pyproject.toml \
    build.gradle build.gradle.kts pom.xml \
    Gemfile composer.json Package.swift pubspec.yaml \
    CMakeLists.txt mix.exs; do
    [ -f "$TEST_LINT_MARK_PROJECT/$TEST_LINT_MARK_MANIFEST" ] && TEST_LINT_MARK_IS_SCRIPT_COLLECTION=0 && break
  done
  if [ "$TEST_LINT_MARK_IS_SCRIPT_COLLECTION" = "1" ] \
    && compgen -G "$TEST_LINT_MARK_PROJECT/*.csproj" >/dev/null 2>&1; then
    TEST_LINT_MARK_IS_SCRIPT_COLLECTION=0
  fi
  if [ "$TEST_LINT_MARK_IS_SCRIPT_COLLECTION" = "1" ] \
    && compgen -G "$TEST_LINT_MARK_PROJECT/*.sln" >/dev/null 2>&1; then
    TEST_LINT_MARK_IS_SCRIPT_COLLECTION=0
  fi
  if [ "$TEST_LINT_MARK_IS_SCRIPT_COLLECTION" = "1" ]; then
    TEST_LINT_MARK_IS_TEST=1
  fi
fi
[ "$TEST_LINT_MARK_IS_TEST" = "1" ] || [ "$TEST_LINT_MARK_IS_LINT" = "1" ] || exit 0
if [ "$TEST_LINT_MARK_RESULT_KIND" = "test" ] && [ "$TEST_LINT_MARK_IS_TEST" != "1" ]; then
  exit 0
fi
if [ "$TEST_LINT_MARK_RESULT_KIND" = "lint" ] && [ "$TEST_LINT_MARK_IS_LINT" != "1" ]; then
  exit 0
fi
if [ "$TEST_LINT_MARK_RESULT_KIND" = "both" ] \
  && { [ "$TEST_LINT_MARK_IS_TEST" != "1" ] || [ "$TEST_LINT_MARK_IS_LINT" != "1" ]; }; then
  exit 0
fi
[ "$TEST_LINT_MARK_IS_TEST" = "1" ] || [ "$TEST_LINT_MARK_IS_LINT" = "1" ] || exit 0

# This marker must be a deterministic, reconstructable path so
# enforce-test-lint-gate.sh's reader can look it up again by session_id
# alone. session_id serves as the uniqueness key here. The namespace is
# codex-hooks, not a repo name — these hooks deploy to ~/.codex/hooks
# and run for every project's session, not just this one.
TEST_LINT_MARK_DIR="${TMPDIR:-/tmp}/codex-hooks/test-lint-guard/${TEST_LINT_MARK_SESSION_ID}"
mkdir -p "$TEST_LINT_MARK_DIR"
chmod 700 "${TMPDIR:-/tmp}/codex-hooks/test-lint-guard" "$TEST_LINT_MARK_DIR" 2>/dev/null || true

# Prune marker dirs older than 1 day — scoped only to this tool's own temp namespace
find "${TMPDIR:-/tmp}/codex-hooks/test-lint-guard" -maxdepth 1 -type d -mtime +1 -exec rm -rf -- {} + 2>/dev/null || true

if [ "$TEST_LINT_MARK_IS_TEST" = "1" ]; then
  TEST_LINT_MARK_TEST_MARKER="$TEST_LINT_MARK_DIR/test"
  grep -qxF -- "$TEST_LINT_MARK_PROJECT" "$TEST_LINT_MARK_TEST_MARKER" 2>/dev/null \
    || printf '%s\n' "$TEST_LINT_MARK_PROJECT" >>"$TEST_LINT_MARK_TEST_MARKER"
fi

if [ "$TEST_LINT_MARK_IS_LINT" = "1" ]; then
  TEST_LINT_MARK_LINT_MARKER="$TEST_LINT_MARK_DIR/lint"
  grep -qxF -- "$TEST_LINT_MARK_PROJECT" "$TEST_LINT_MARK_LINT_MARKER" 2>/dev/null \
    || printf '%s\n' "$TEST_LINT_MARK_PROJECT" >>"$TEST_LINT_MARK_LINT_MARKER"
fi

exit 0

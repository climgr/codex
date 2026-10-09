#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202610090001-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  test-lint-run.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Friday, October 2, 2026 00:01 EDT
# @@File             :  test-lint-run.sh
# @@Description      :  Runs a test or lint command, records its completed status, and emits a gate result sentinel.
# @@Changelog        :  20261009: Record gate success before returning, including commands polled by session ID.
# @@TODO             :  None
# @@Other            :  Usage: test-lint-run.sh {test|lint|both} -- command [args...]
# @@Resource         :  home/hooks/test-lint-mark.sh, home/hooks/enforce-test-lint-gate.sh
# @@Terminal App     :  no
# @@sudo/root        :  no
# @@Template         :  shell/bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC1001,SC1003,SC2001,SC2003,SC2016,SC2031,SC2090,SC2115,SC2120,SC2155,SC2199,SC2229,SC2317,SC2329
# - - - - - - - - - - - - - - - - - - - - - - - - -
VERSION="202610090001-git"
# - - - - - - - - - - - - - - - - - - - - - - - - -
set -uo pipefail

if [ "$#" -lt 3 ]; then
  printf 'Usage: %s {test|lint|both} -- command [args...]\n' "${0##*/}" >&2
  exit 2
fi

CODEX_GATE_KIND="$1"
shift
if [ "$1" != "--" ]; then
  printf 'Usage: %s {test|lint|both} -- command [args...]\n' "${0##*/}" >&2
  exit 2
fi
shift
if [ "$#" -eq 0 ]; then
  printf 'A gate command is required\n' >&2
  exit 2
fi
case "$CODEX_GATE_KIND" in
  test | lint | both) ;;
  *)
    printf 'Unknown gate kind: %s\n' "$CODEX_GATE_KIND" >&2
    exit 2
    ;;
esac

# Only known test and lint command prefixes may produce a gate marker. This
# prevents a successful `echo "make test"` or similar from satisfying a gate.
CODEX_GATE_TEST=0
CODEX_GATE_LINT=0
case "${1-}:${2-}:${3-}" in
  make:test:* | make:check:* | go:test:* | cargo:test:* | pytest:* | npm:test:* | npm:run:test:* \
    | jq:empty:* | gradle:test:* | ./gradlew:test:* | mvn:test:* | rspec:* \
    | bundle:exec:rspec* | rake:test:* | phpunit:* | composer:test:* \
    | swift:test:* | flutter:test:* | dart:test:* | ctest:* | dotnet:test:* \
    | mix:test:* | bash:-n:* | sh:-n:*) CODEX_GATE_TEST=1 ;;
esac
case "${1-}:${2-}:${3-}" in
  shellcheck:*:* | golangci-lint:run:* | go:vet:* | cargo:clippy:* \
    | script-lint:*:* | go-lint:*:* | rust-lint:*:* | npm:run:lint:* | npx:eslint:* \
    | ruff:check:* | ruff:format:--check* | make:check:* | taplo:lint:* \
    | lintian:*:* | rpmlint:*:* | namcap:*:* | apkbuild-lint:*:* \
    | brew:audit:* | brew:style:* | snapcraft:lint:* | flatpak-builder-lint:*:* \
    | appimagelint:*:* | nix:flake:check* | statix:*:* | gradle:lint:* \
    | gradle:ktlintCheck:* | gradle:detekt:* | ./gradlew:lint:* \
    | ./gradlew:ktlintCheck:* | ./gradlew:detekt:* | mvn:checkstyle:check* \
    | mvn:spotbugs:check* | rubocop:*:* | phpcs:*:* | php-cs-fixer:*:* \
    | phpstan:*:* | swiftlint:*:* | flutter:analyze:* | dart:analyze:* \
    | clang-tidy:*:* | cppcheck:*:* | dotnet:format:--verify-no-changes* \
    | mix:credo:* | mix:format:--check-formatted*) CODEX_GATE_LINT=1 ;;
esac
if [ "$CODEX_GATE_KIND" = "test" ] && [ "$CODEX_GATE_TEST" != "1" ]; then
  printf 'Not a recognized test command: %s\n' "$1" >&2
  exit 2
fi
if [ "$CODEX_GATE_KIND" = "lint" ] && [ "$CODEX_GATE_LINT" != "1" ]; then
  printf 'Not a recognized lint command: %s\n' "$1" >&2
  exit 2
fi
if [ "$CODEX_GATE_KIND" = "both" ] && { [ "$CODEX_GATE_TEST" != "1" ] || [ "$CODEX_GATE_LINT" != "1" ]; }; then
  printf 'A recognized combined test and lint command is required\n' >&2
  exit 2
fi

CODEX_GATE_TMP_ROOT="${TMPDIR:-/tmp}/codex-hooks/gate-output"
mkdir -p "$CODEX_GATE_TMP_ROOT" || exit 1
chmod 700 "${TMPDIR:-/tmp}/codex-hooks" "$CODEX_GATE_TMP_ROOT" 2>/dev/null || true
CODEX_GATE_OUTPUT="$(mktemp "$CODEX_GATE_TMP_ROOT/output.XXXXXX")" || exit 1
trap 'rm -f -- "$CODEX_GATE_OUTPUT"' EXIT

"$@" >"$CODEX_GATE_OUTPUT" 2>&1
CODEX_GATE_STATUS=$?
if [ "$CODEX_GATE_STATUS" -eq 0 ]; then
  CODEX_GATE_SESSION_ID="${CODEX_SESSION_ID:-}"
  CODEX_GATE_RUNNER_PATH="$(realpath -- "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
  CODEX_GATE_MARKER_SCRIPT="${CODEX_GATE_RUNNER_PATH%/*}/test-lint-mark.sh"
  if [[ ! "$CODEX_GATE_SESSION_ID" =~ ^[A-Za-z0-9._-]+$ ]] || ! command -v jq >/dev/null 2>&1; then
    printf 'Unable to record the test/lint gate: this Codex session lacks a valid session id or jq.\n' >&2
    CODEX_GATE_STATUS=1
  else
    # The process environment session id lets the runner record completion
    # even when Codex returns a session handle before this child exits.
    CODEX_GATE_MARKER_COMMAND="bash \"$CODEX_GATE_RUNNER_PATH\" $CODEX_GATE_KIND --"
    for CODEX_GATE_ARG in "$@"; do
      printf -v CODEX_GATE_ESCAPED_ARG '%q' "$CODEX_GATE_ARG"
      CODEX_GATE_MARKER_COMMAND+=" $CODEX_GATE_ESCAPED_ARG"
    done
    if ! CODEX_GATE_MARKER_EVENT=$(jq -cn \
      --arg session_id "$CODEX_GATE_SESSION_ID" \
      --arg cwd "$PWD" \
      --arg command "$CODEX_GATE_MARKER_COMMAND" \
      --arg result "CODEX_TEST_LINT_GATE_V1:PASS:$CODEX_GATE_KIND" \
      '{session_id:$session_id,cwd:$cwd,tool_name:"Bash",tool_input:{command:$command},tool_response:$result}'); then
      printf 'Unable to build the completed test/lint gate marker.\n' >&2
      CODEX_GATE_STATUS=1
    elif ! printf '%s\n' "$CODEX_GATE_MARKER_EVENT" | bash "$CODEX_GATE_MARKER_SCRIPT" >/dev/null; then
      printf 'Unable to record the completed test/lint gate marker.\n' >&2
      CODEX_GATE_STATUS=1
    else
      CODEX_GATE_PROJECT=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD")
      CODEX_GATE_PROJECT=$(realpath -- "$CODEX_GATE_PROJECT" 2>/dev/null || printf '%s' "$CODEX_GATE_PROJECT")
      CODEX_GATE_MARKER_DIR="${TMPDIR:-/tmp}/codex-hooks/test-lint-guard/$CODEX_GATE_SESSION_ID"
      if { [ "$CODEX_GATE_KIND" = "test" ] || [ "$CODEX_GATE_KIND" = "both" ]; } \
        && ! grep -qxF -- "$CODEX_GATE_PROJECT" "$CODEX_GATE_MARKER_DIR/test" 2>/dev/null; then
        printf 'The test command completed but did not produce a valid test-gate marker for this project.\n' >&2
        CODEX_GATE_STATUS=1
      fi
      if { [ "$CODEX_GATE_KIND" = "lint" ] || [ "$CODEX_GATE_KIND" = "both" ]; } \
        && ! grep -qxF -- "$CODEX_GATE_PROJECT" "$CODEX_GATE_MARKER_DIR/lint" 2>/dev/null; then
        printf 'The lint command completed but did not produce a valid lint-gate marker for this project.\n' >&2
        CODEX_GATE_STATUS=1
      fi
    fi
  fi
fi
if [ "$CODEX_GATE_STATUS" -eq 0 ]; then
  printf 'CODEX_TEST_LINT_GATE_V1:PASS:%s\n' "$CODEX_GATE_KIND"
else
  printf 'CODEX_TEST_LINT_GATE_V1:FAIL:%s\n' "$CODEX_GATE_KIND"
fi
cat -- "$CODEX_GATE_OUTPUT"
exit "$CODEX_GATE_STATUS"

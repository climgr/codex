#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202609031612-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  spec-guard.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Monday, July 20, 2026 00:00 EDT
# @@File             :  spec-guard.sh
# @@Description      :  PreToolUse hook: block Edit/Write on project files until AI.md/SPEC.md was read this session
# @@Changelog        :  Wrapped two long BLOCKED message strings onto multiple lines to fix line-length violations.
# @@TODO             :
# @@Other            :  Gates only repos with AI.md/SPEC.md; project instruction files are optional; exempt: meta/spec, README/LICENSE, COMMIT_MESS, env, .no_push.
# @@Resource         :  ~/.codex/memory/project_conventions.md
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC2034
VERSION="202609031612-git"
# - - - - - - - - - - - - - - - - - - - - - - - - -

set -euo pipefail

# Fail open when jq is missing — a broken hook must never block every Edit/Write
if ! command -v jq >/dev/null 2>&1; then
  printf 'spec-guard.sh: jq not found — spec guard disabled\n' >&2
  exit 0
fi

SPEC_GUARD_INPUT="$(cat)"

# Fail open on an empty, malformed, or non-object payload. Without this, jq
# exits 4/5 and `set -e` propagates that code, which Codex surfaces as a
# "hook error" instead of the silent no-op Part 6 requires on a parse failure.
if ! printf '%s' "$SPEC_GUARD_INPUT" | jq -e 'type == "object"' >/dev/null 2>&1; then
  exit 0
fi

SPEC_GUARD_FILE_PATH=$(printf '%s' "$SPEC_GUARD_INPUT" | jq -r 'try (.tool_input.file_path) catch "" // ""')
SPEC_GUARD_SESSION_ID=$(printf '%s' "$SPEC_GUARD_INPUT" | jq -r '.session_id // ""')
[ -z "$SPEC_GUARD_FILE_PATH" ] && exit 0
[ -z "$SPEC_GUARD_SESSION_ID" ] && exit 0

# Exempt meta/spec and instruction files — these are pre-approved to edit without
# having read AI.md first (editing the governing documents is not implementation).
case "$SPEC_GUARD_FILE_PATH" in
  */.git/* | */.codex/*) exit 0 ;;
esac
case "${SPEC_GUARD_FILE_PATH##*/}" in
  AI.md | IDEA.md | SPEC.md | AGENTS.md | CLAUDE.md | TODO.AI.md | TODO.md | PLAN.AI.md | PLAN.md \
    | COMMIT_MESS | .env | app.env | default.env | .no_push | README.md | LICENSE.md)
    exit 0
    ;;
esac

SPEC_GUARD_PROJECT=$(git -C "${SPEC_GUARD_FILE_PATH%/*}" rev-parse --show-toplevel 2>/dev/null) || exit 0

# AI.md and SPEC.md opt projects into this guard. Other instruction files
# (including AGENTS.md and CLAUDE.md) may stand alone without requiring either.
if [ ! -f "$SPEC_GUARD_PROJECT/AI.md" ] && [ ! -f "$SPEC_GUARD_PROJECT/SPEC.md" ]; then
  exit 0
fi

SPEC_GUARD_MARKER="${TMPDIR:-/tmp}/codex-hooks/spec-guard/${SPEC_GUARD_SESSION_ID}/read"
grep -qxF -- "$SPEC_GUARD_PROJECT" "$SPEC_GUARD_MARKER" 2>/dev/null && exit 0

SPEC_GUARD_MSG="BLOCKED: Spec guard — this project's AI.md/SPEC.md has not been read yet this session.
project_dir: ${SPEC_GUARD_PROJECT}
Before editing project files: read the section relevant to this task from
AI.md if present, otherwise SPEC.md. If both exist, also read any applicable
SPEC.md rules. Then retry this edit.
This gate re-arms after every compaction — re-read the spec again after a compact before resuming edits."

printf '%s\n' "$SPEC_GUARD_MSG"
printf '%s\n' "$SPEC_GUARD_MSG" >&2
exit 2

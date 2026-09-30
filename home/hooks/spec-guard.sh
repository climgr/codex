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
# @@Other            :  Gates repos with AI.md/SPEC.md; bare AGENTS.md is a blocked broken bootstrap; exempt: meta/spec, README/LICENSE, COMMIT_MESS, env, .no_push.
# @@Resource         :  ~/.codex/memory/project_conventions.md
# - - - - - - - - - - - - - - - - - - - - - - - - -
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

# Exempt meta/spec files — these are pre-approved to edit without having read AI.md first
# (editing AI.md itself, or IDEA.md/SPEC.md/TODO/PLAN, is not "implementing against the spec")
case "$SPEC_GUARD_FILE_PATH" in
  */.git/* | */.codex/*) exit 0 ;;
esac
case "${SPEC_GUARD_FILE_PATH##*/}" in
  AI.md | IDEA.md | SPEC.md | AGENTS.md | TODO.AI.md | TODO.md | PLAN.AI.md | PLAN.md \
    | COMMIT_MESS | .env | app.env | default.env | .no_push | README.md | LICENSE.md)
    exit 0
    ;;
esac

SPEC_GUARD_PROJECT=$(git -C "${SPEC_GUARD_FILE_PATH%/*}" rev-parse --show-toplevel 2>/dev/null) || exit 0

# Existence precedence: AI.md (THE HOW, primary spec) > AGENTS.md (loader —
# its presence without AI.md means a broken bootstrap, not "ungoverned") >
# SPEC.md (project-rule overrides; gates on its own if AI.md is absent too)
if [ -f "$SPEC_GUARD_PROJECT/AI.md" ]; then
  :
elif [ -f "$SPEC_GUARD_PROJECT/AGENTS.md" ] && [ ! -f "$SPEC_GUARD_PROJECT/SPEC.md" ]; then
  SPEC_GUARD_MSG="BLOCKED: Spec guard — this project has a AGENTS.md loader but no AI.md/SPEC.md for it to load.
project_dir: ${SPEC_GUARD_PROJECT}
The loader implies this project was meant to be spec-governed. Bootstrap
AI.md first (copy the matching go/rust/android template, or use the
bootstrap/spec-migrator agent), then retry this edit."
  printf '%s\n' "$SPEC_GUARD_MSG"
  printf '%s\n' "$SPEC_GUARD_MSG" >&2
  exit 2
elif [ ! -f "$SPEC_GUARD_PROJECT/SPEC.md" ]; then
  # Neither AI.md, AGENTS.md, nor SPEC.md — nothing to gate on
  exit 0
fi

SPEC_GUARD_MARKER="${TMPDIR:-/tmp}/codex-hooks/spec-guard/${SPEC_GUARD_SESSION_ID}/read"
grep -qxF -- "$SPEC_GUARD_PROJECT" "$SPEC_GUARD_MARKER" 2>/dev/null && exit 0

SPEC_GUARD_MSG="BLOCKED: Spec guard — AI.md/SPEC.md for this project has not been read yet this session.
project_dir: ${SPEC_GUARD_PROJECT}
Before editing project files: search AI.md for the section relevant to
this task — it may use '## Part N' headings, '# PART N' headings, or no
headings at all (if short, just Read the whole file). Read that section
(and SPEC.md if present), then retry this edit.
This gate re-arms after every compaction — re-read the spec again after a compact before resuming edits."

printf '%s\n' "$SPEC_GUARD_MSG"
printf '%s\n' "$SPEC_GUARD_MSG" >&2
exit 2

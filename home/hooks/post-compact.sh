#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202609170001-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  post-compact.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Friday, May 16, 2026 00:00 EDT
# @@File             :  post-compact.sh
# @@Description      :  SessionStart(compact) hook: re-inject project-dir and global context after compaction
# @@Changelog        :  Fail open (exit 0) when python3 is missing instead of surfacing a hook error under set -e.
# @@TODO             :
# @@Other            :  Compaction drops old context; this re-anchors Codex to the project without a full re-read, which previously re-triggered compaction in a loop.
# @@Resource         :
# - - - - - - - - - - - - - - - - - - - - - - - - -
VERSION="202609170001-git"
# - - - - - - - - - - - - - - - - - - - - - - - - -

set -euo pipefail

# Drain stdin (session-start payload) — must consume it
POST_COMPACT_INPUT="$(cat)"

# Fail open (exit 0, no context) when the JSON emitter is missing — under
# set -e a missing python3 would otherwise surface as a hook error.
command -v python3 >/dev/null 2>&1 || exit 0

# Clear this session's spec-guard marker so AI.md/SPEC.md must be re-read after compaction
# The `type == "object"` probe fails open on an empty, malformed, or non-object
# payload: without it jq exits 4/5 and `set -e` propagates that code, which
# Codex surfaces as a "hook error" and skips the context injection below.
if command -v jq >/dev/null 2>&1 && printf '%s' "$POST_COMPACT_INPUT" | jq -e 'type == "object"' >/dev/null 2>&1; then
  POST_COMPACT_SESSION_ID=$(printf '%s' "$POST_COMPACT_INPUT" | jq -r 'try (.session_id) catch "" // ""')
  [ -n "$POST_COMPACT_SESSION_ID" ] && rm -rf -- "${TMPDIR:-/tmp}/codex-hooks/spec-guard/${POST_COMPACT_SESSION_ID}"
fi

POST_COMPACT_PROJECT=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -f "$POST_COMPACT_PROJECT/AGENTS.md" ] || [ -f "$POST_COMPACT_PROJECT/AI.md" ] || exit 0

POST_COMPACT_MSG="POST-COMPACT CONTEXT
project_dir: ${POST_COMPACT_PROJECT}
Context was compacted. The summary above is your state — resume from its task goal and next actions.
Do NOT bulk re-read files now; that refills context immediately and can trigger another compaction.
1. Project AGENTS.md/AI.md/SPEC.md still override the global AGENTS.md, but consult them on demand —
   read only the specific section your next action needs, not the whole file
2. Before editing a file, re-read only that file (or the relevant section) — don't proactively re-read files you are not about to touch
3. All writes must stay within ${POST_COMPACT_PROJECT} unless the user explicitly names an external path
4. spec-guard.sh will block Edit/Write until AI.md/SPEC.md is Read again this session — it fires on its own when you attempt an edit; no need to pre-emptively satisfy it"

python3 -c "
import json, sys
print(json.dumps({'hookSpecificOutput': {'hookEventName': 'SessionStart', 'additionalContext': sys.argv[1]}}))
" "$POST_COMPACT_MSG"

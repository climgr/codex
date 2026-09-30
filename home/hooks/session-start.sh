#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202609170001-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  session-start.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Friday, May 16, 2026 00:00 EDT
# @@File             :  session-start.sh
# @@Description      :  SessionStart hook: inject project-dir context to anchor every session
# @@Changelog        :  Drain stdin and fail open (exit 0) when python3 is missing instead of surfacing a hook error under set -e.
# @@TODO             :
# @@Other            :  Silently exits if not inside a git repo with a project AGENTS.md or AI.md
# @@Resource         :
# - - - - - - - - - - - - - - - - - - - - - - - - -
VERSION="202609170001-git"
# - - - - - - - - - - - - - - - - - - - - - - - - -

set -euo pipefail

# Drain the payload so Codex never sees a broken pipe, and fail open
# (exit 0, no context) when the JSON emitter is missing — under set -e a
# missing python3 would otherwise surface as a hook error on every start.
cat >/dev/null || :
command -v python3 >/dev/null 2>&1 || exit 0

project=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null) || exit 0

has_agents=0
has_ai=0
has_spec=0
[ -f "$project/AGENTS.md" ] && has_agents=1
[ -f "$project/AI.md" ] && has_ai=1
[ -f "$project/SPEC.md" ] && has_spec=1

# Only fire when the project has a AGENTS.md or AI.md (a managed project)
[ "$has_agents" -eq 1 ] || [ "$has_ai" -eq 1 ] || exit 0

LINES=("SESSION CONTEXT" "project_dir: ${project}")
if [ "$has_agents" -eq 1 ]; then
  LINES+=("Read ${project}/AGENTS.md first — it is a short loader; this project's real spec lives in AI.md (THE HOW) and IDEA.md (THE WHAT).")
fi
LINES+=("Project AGENTS.md and AI.md are the source of truth for this session — they override the global ~/.codex/AGENTS.md.")
if [ "$has_spec" -eq 1 ]; then
  LINES+=("SPEC.md exists — it overrides AI.md for any rule it addresses. Precedence: SPEC.md > AI.md > global AGENTS.md.")
fi
LINES+=("All writes must stay within ${project} unless the user explicitly names an external path.")
if [ "$has_ai" -eq 1 ]; then
  LINES+=("Read AI.md and IDEA.md before acting on this project.")
fi

MSG=$(printf '%s\n' "${LINES[@]}")

python3 -c "
import json, sys
print(json.dumps({'hookSpecificOutput': {'hookEventName': 'SessionStart', 'additionalContext': sys.argv[1]}}))
" "$MSG"

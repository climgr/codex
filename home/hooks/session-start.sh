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
# @@Other            :  Silently exits if not inside a git repo with project instruction/spec files
# @@Resource         :
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC2034
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
has_idea=0
has_claude=0
[ -f "$project/AGENTS.md" ] && has_agents=1
[ -f "$project/AI.md" ] && has_ai=1
[ -f "$project/SPEC.md" ] && has_spec=1
[ -f "$project/IDEA.md" ] && has_idea=1
[ -f "$project/CLAUDE.md" ] && has_claude=1

# These files are optional; inject context only for those present.
[ "$has_agents" -eq 1 ] || [ "$has_ai" -eq 1 ] || [ "$has_spec" -eq 1 ] || [ "$has_idea" -eq 1 ] || [ "$has_claude" -eq 1 ] || exit 0

LINES=("SESSION CONTEXT" "project_dir: ${project}")
if [ "$has_agents" -eq 1 ] || [ "$has_claude" -eq 1 ]; then
  instruction_files=()
  [ "$has_agents" -eq 1 ] && instruction_files+=("${project}/AGENTS.md")
  [ "$has_claude" -eq 1 ] && instruction_files+=("${project}/CLAUDE.md")
  LINES+=("Read the project's instruction files: ${instruction_files[*]}.")
fi
if [ "$has_ai" -eq 1 ] || [ "$has_spec" -eq 1 ] || [ "$has_idea" -eq 1 ]; then
  project_docs=()
  [ "$has_ai" -eq 1 ] && project_docs+=("AI.md")
  [ "$has_spec" -eq 1 ] && project_docs+=("SPEC.md")
  [ "$has_idea" -eq 1 ] && project_docs+=("IDEA.md")
  LINES+=("Project documentation present: ${project_docs[*]}. Consult the files relevant to this task; these files are optional.")
fi
if [ "$has_spec" -eq 1 ]; then
  if [ "$has_ai" -eq 1 ]; then
    LINES+=("SPEC.md overrides AI.md for any rule it addresses.")
  fi
fi
LINES+=("All writes must stay within ${project} unless the user explicitly names an external path.")

MSG=$(printf '%s\n' "${LINES[@]}")

python3 -c "
import json, sys
print(json.dumps({'hookSpecificOutput': {'hookEventName': 'SessionStart', 'additionalContext': sys.argv[1]}}))
" "$MSG"

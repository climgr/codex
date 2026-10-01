#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202609020210-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  no-ai-attribution.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Tuesday, May 13, 2026 00:00 EDT
# @@File             :  no-ai-attribution.sh
# @@Description      :  Codex PreToolUse hook - block AI attribution phrases in written content
# @@Changelog        :  Streams the content through one sed+grep pass instead of per line, and writes the BLOCKED reason to both streams.
# @@TODO             :  See project issues
# @@Other            :  Fires on Write and Edit tool use; blocks attribution trailers/comments only
# @@Resource         :  Codex lifecycle hooks
# @@Terminal App     :  no
# @@sudo/root        :  no
# @@Template         :  shell/bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC1001,SC1003,SC2001,SC2003,SC2016,SC2031,SC2090,SC2115,SC2120,SC2155,SC2199,SC2229,SC2317,SC2329
# - - - - - - - - - - - - - - - - - - - - - - - - -
VERSION="202609020210-git"
# - - - - - - - - - - - - - - - - - - - - - - - - -
set -uo pipefail
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Patterns that constitute AI attribution. Match only phrases where an AI
# tool is credited as the author/generator — NOT bare product names used
# in documentation, filenames, or tool references.
#
# Blocked (verb + connector + AI name, plus trailer forms):
#   verbs: Generated / Written / Created / Authored / Built / Made / Assisted
#   connectors: by / with / using
#   names: coding assistants and AI providers listed in _assistant_names
#   trailers: Co-Authored-By and Co-Authored By forms naming those assistants
#   (ASCII hyphen or Unicode non-breaking hyphen U+2011 between the words),
#   the "AI" + hyphen + "generated" adjective, robot-emoji attribution lines
#
# NOT blocked:
#   AGENTS.md (filename)       Codex hook
#   Using Codex                OpenAI API docs
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Pattern pieces are assembled from split strings so this file never trips its own scanner
_verbs='(generated|written|created|authored|built|made|assisted)'
_conn='(by|with|using)'
_assistant_names='(codex|openai|chatgpt|chat[ -]?gpt|gpt([- ][[:alnum:].]+)?'
_assistant_names="${_assistant_names}|claude|anthropic|gemini|github copilot|copilot"
_assistant_names="${_assistant_names}|cursor|windsurf|perplexity|deepseek|mistral|qwen|llama)"
_ai="(${_assistant_names}|an? ai\b)"
# ASCII hyphen or Unicode non-breaking hyphen (U+2011) between trailer words
_hyph='(-|‑)'
_ca="co${_hyph}authored${_hyph}by"
_gen='generated'
ATTRIBUTION_PATTERN="${_verbs}[[:space:]]+${_conn}[[:space:]]+${_ai}"
ATTRIBUTION_PATTERN="${ATTRIBUTION_PATTERN}|${_ca}:[[:space:]]*${_assistant_names}"
ATTRIBUTION_PATTERN="${ATTRIBUTION_PATTERN}|co_authored_by:[[:space:]]*${_assistant_names}"
ATTRIBUTION_PATTERN="${ATTRIBUTION_PATTERN}|co[- ]?authored[[:space:]]+(by|with)[[:space:]]*${_assistant_names}"
ATTRIBUTION_PATTERN="${ATTRIBUTION_PATTERN}|\bai[- ]${_gen}\b|🤖[[:space:]]*${_verbs}"
ATTRIBUTION_FILE_CREDIT="(this[[:space:]]+file[[:space:]]+(was|is)[[:space:]]+"
ATTRIBUTION_FILE_CREDIT="${ATTRIBUTION_FILE_CREDIT}(${_gen}|written|created)[[:space:]]+by[[:space:]]+"
ATTRIBUTION_FILE_CREDIT="${ATTRIBUTION_FILE_CREDIT}(${_assistant_names}|ai\b))"
ATTRIBUTION_PATTERN="${ATTRIBUTION_PATTERN}|${ATTRIBUTION_FILE_CREDIT}"
# - - - - - - - - - - - - - - - - - - - - - - - - -
__require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'no-ai-attribution.sh: required command not found: %s\n' "$1" >&2
    exit 0
  fi
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
__extract_content() {
  python3 -c '
import json, sys
try:
    d = json.load(sys.stdin).get("tool_input", {})
    # Write tool uses "content"; Edit tool uses "new_string"
    print(d.get("content") or d.get("new_string") or "")
except Exception:
    print("")
'
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
__require_cmd python3
__require_cmd grep
# - - - - - - - - - - - - - - - - - - - - - - - - -
INPUT="$(cat)"
CONTENT="$(printf '%s' "$INPUT" | __extract_content)"
# - - - - - - - - - - - - - - - - - - - - - - - - -
[ -z "$CONTENT" ] && exit 0
# - - - - - - - - - - - - - - - - - - - - - - - - -
# AGENTS.md's Output section scopes this rule to trailers/footers ("no
# Co-Authored-By:, AI-tool trailers, or 'Generated with X' footers") — not
# to any file that merely discusses the phrase as a topic. A bare substring
# match anywhere in the content also flags prose ABOUT the rule (this file's
# own header needed rewording once to dodge that). Anchor the match to the
# start of each line, after stripping common comment/quote/blockquote
# leaders, so a genuine standalone trailer line still blocks but a
# mid-sentence mention or quoted example does not.
# sed and grep are both line-oriented, so streaming the whole content through
# each of them once is identical in meaning to testing one line at a time —
# `sed` strips leaders per line and `^` still anchors per line. The previous
# per-line `while read` spawned a sed AND a grep for every line, which grew
# quadratically: an 8KB file took ~24s against this hook's 10s timeout
# timeout, so any sizable Write/Edit failed as a hook error instead of passing.
if printf '%s\n' "$CONTENT" \
  | sed -E 's/^[[:space:]]*(#|\/\/|<!--|\*|-|>)+[[:space:]]*//; s/^[[:space:]]*["'"'"'`]+//' \
  | grep -qiE -- "^(${ATTRIBUTION_PATTERN})"; then
  # AI.md Part 6's blocking-output format writes the reason to both streams:
  # stderr so Codex feeds it back as the block reason, stdout so the
  # same text is also captured in the session transcript.
  printf 'BLOCKED: AI attribution phrase detected in file content.\n'
  printf 'Remove lines like "Generated %s Codex", "Co%sAuthored%sBy: Codex", or "AI%sgenerated".\n' 'by' '-' '-' '-'
  printf 'BLOCKED: AI attribution phrase detected in file content.\n' >&2
  printf 'Remove lines like "Generated %s Codex", "Co%sAuthored%sBy: Codex", or "AI%sgenerated".\n' 'by' '-' '-' '-' >&2
  exit 2
fi
# - - - - - - - - - - - - - - - - - - - - - - - - -
exit 0

---
name: Drift prevention conventions
description: the pre-edit self-check checklist, post-compaction lazy re-verification, project_dir resolution from SessionStart/PostCompact context, and the /clear SessionStart-hook-bug workaround
type: user
---

# Drift Prevention Conventions

Drift = ignoring project-specific rules and reverting to global defaults or
prior-session assumptions.

## Self-Check Before Any Read or Write

1. Is this path inside `{project_dir}`?
2. Does this project have its own version of this file (AI.md, AGENTS.md,
   memory files)?
3. Am I applying a rule from THIS project's files, not a global assumption?
4. Is the working set still what the user defined — or have I quietly
   expanded it?

This self-check must be answered explicitly (in output or reasoning), not
silently assumed — skipping it is how stale global-default behavior sneaks
back in after a compaction.

## Post-Compaction Lazy Re-Verification

Do not bulk re-read AGENTS.md/AI.md/SPEC.md after a compaction — that refills
context immediately and can trigger another compaction (`post-compact.sh`
deliberately does not inject the full files for this reason). Instead, treat
every rule as needing re-verification lazily: before each edit, search for
and read only the specific section of AGENTS.md/AI.md/SPEC.md relevant to
that edit (`grep -n "^## "` or the file's own heading style to find it), the
same technique the `TODO.AI.md` PART-loading rule uses. Never assume a rule
from before the compaction still holds without checking its source section
first.

## project_dir Resolution

If a SessionStart or PostCompact system message references a `project_dir`:
that path IS `{project_dir}` for this session.

## `/clear` Note

`SessionStart` hooks (including `session-start.sh`'s project_dir context
injection) are documented to fire on `/clear` but do not, due to a confirmed
upstream Codex bug (`Codex SessionStart behavior`, closed
not-planned). This isn't a gap in practice: `{project_dir}` is already
self-derived from `git rev-parse --show-toplevel`, falling back to `$PWD`
when not in a git repo, not from the hook's injected text — so re-run the
Session Start sync sequence yourself after any `/clear` using that same
resolution; don't wait for hook-injected context that won't arrive.

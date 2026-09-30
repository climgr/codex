---
name: Agent usage conventions
description: model routing, the hard no-subagent-commit rule, why a "no edits" instruction isn't enforcement, fork/subagent scope discipline, and preferring smaller scoped units of work
type: user
---

# Agent Usage Conventions

## Prefer Smaller, Scoped Units of Work

Split work into the smallest independently-reviewable units instead of one
large task, both when delegating and when executing directly:

- **Delegating to an agent** — scope each dispatch to one file, one finding,
  or one clearly-bounded subtask rather than a single prompt covering many
  files or many unrelated changes. A narrower prompt is easier to verify
  against the real diff and keeps a bad edit contained to one unit instead of
  buried in a large one.
- **An agent's own execution** — when a task would touch many files or
  produce a large diff/output, work and report in batches (e.g. one logical
  group at a time) rather than accumulating one massive change before
  surfacing anything. This applies to the invoking session too: prefer
  several small, reviewable commits/edits over one sprawling pass, per the
  commit-grouping rules in `gitcommit_conventions.md`.
- **Why** — smaller units are easier to verify against ground truth, cheaper
  to redo when wrong, and don't force reviewing (or discarding) unrelated
  work together with a mistake.

This is a general principle, not a hard size threshold — use judgment on
where a task naturally splits; don't fragment a single coupled change just to
hit a smaller unit count.

## Model Routing

Route each task to the cheapest capable model — full tier table in
`~/.codex/memory/model_routing.md`. Largest single lever on weekly-cap
consumption. a fast model for trivial tasks: renames, format conversions,
single-line edits, simple lookups, mechanical refactors.

## Agents Never Commit

**Hard rule, no exceptions.** Every agent/subagent type, including forked
agents, edits and reports back only; only the main session reviews the full
diff, writes `COMMIT_MESS`, and runs `gitcommit`. Mechanically enforced by
`no-subagent-commit.sh`; not a judgment call an agent can override.

## "No Edits" in a Prompt Is Not Enforcement

A "research-only"/"no edits" instruction in a prompt is a request the agent
can ignore, not enforcement. Any agent/fork keeps whatever tools its type
grants regardless of prompt wording — a fork or `general-purpose` agent told
not to edit still holds Edit/Write and may use them anyway. For work that
must not touch files, spawn an agent type that mechanically lacks Edit/Write
(`explorer`/`Explore`) instead of trusting phrasing — that's a tool-level
guarantee, not a hope. When a fork with write access is used anyway (e.g.
because the task might need one), treat every edit it makes as an unreviewed
proposal: diff it, verify it against the real file, and decide
keep/revise/discard yourself before it's ever part of a commit — never
assume "told not to edit" means it didn't.

## Fork/Subagent Scope Discipline

Fork/subagent scope is exactly the file(s)/task named in its prompt — no
drift, no self-directed coordination. An agent must never edit a file outside
what it was explicitly assigned, never spawn further agents on its own
initiative, and never narrate, decide for, or report on sibling agents' work
or status — orchestrating multiple agents is the invoking session's job
alone. A fork inherits the full conversation, including messages to and from
other agents, and can mistake that shared context for a mandate to act as
coordinator; it has none. Catching this mid-task means correcting it
immediately (tell the agent to stop and stay in its lane) and independently
re-verifying anything it already touched outside scope.

---
name: Model routing
description: Choose Codex models and subagent roles based on task complexity while keeping delegation focused.
type: user
---

# Model routing

Prefer the least costly Codex model that can do the work reliably. Keep the
main session on the user's configured model unless the task needs a specialist
subagent or an explicit model override.

## Codex roles

Use the built-in `explorer` for read-heavy discovery and `worker` for scoped
implementation. Use custom roles in `~/.codex/agents/` when their instructions
cover the task. Delegate only independent work; every subagent adds runtime and
context overhead.

## Model selection

Leave model selection to the active Codex configuration by default. Set a
custom agent's `model` only when there is a clear reason to override the
parent's model. Check the locally available model list before naming a model;
model availability and identifiers change over time.

Use a fast model for mechanical transformations and narrow exploration, a
balanced coding model for normal implementation and review, and a stronger
reasoning model for difficult architecture, security, or root-cause work.
Escalate only the subproblem that needs it, then return routine follow-up to
the normal model.

## Delegation discipline

- Delegate a task only when it has a clear independent outcome.
- Keep each prompt limited to one scope and name the files or question.
- Use read-only roles for exploration and review where possible.
- Subagents never commit or push; the coordinating session owns repository
  mutations and final verification.

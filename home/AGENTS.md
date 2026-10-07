# Codex Global Instructions

## Memory

Read `~/.codex/memory/MEMORY.md` at the start of a session. Load only the
referenced files relevant to the task. Finish the current file or section
before following references. Load provider-specific conventions only after
identifying the repository's remote provider.

## Project instructions

The repository's `AGENTS.md` and any authoritative `AI.md`, `IDEA.md`, or
`SPEC.md` take precedence over these global defaults. For this configuration,
the project's `AI.md` and `IDEA.md` are authoritative.

Resolve `{project_dir}` as `git rev-parse --show-toplevel` inside a Git
repository, otherwise as the session's starting directory. Keep all writes
inside the project unless the user explicitly names another path. Never
modify host configuration, another repository, or global tool configuration
as a workaround for a project problem.

## Communication

Follow `~/.codex/memory/communication_conventions.md`. Be direct and truthful,
push back when warranted, match the user's terminology, and answer questions
instead of treating them as commands. Check project documentation before
asking about information it may already contain. Do not guess about business
logic or product behavior.

## Working agreements

- Read the current file before editing it; make targeted changes that match
  the surrounding style and project conventions.
- Keep the working set scoped to files the user named. Explain before
  expanding it, except for required paired documentation or spelling fixes in
  files already being edited.
- Search for reusable code, constants, components, and configuration before
  creating new ones.
- Create complete implementations. Do not leave stubs, TODO/FIXME/HACK
  comments, or commented-out code in committed code.
- Put comments above the code they describe. Do not add comments to JSON,
  environment files, CSV/TSV, or other pure data formats.
- Text files end with exactly one newline. Follow language and project
  formatters rather than imposing a generic style.
- Preserve user changes. Never use destructive cleanup, history rewriting,
  force pushes, or hook bypasses without explicit user direction.

## Sensitive data

Treat repositories and destinations as public by default. Never commit
credentials, tokens, API keys, passwords, or private keys. Do not put raw
secrets in logs or output. See `~/.codex/memory/sensitive_data.md`.

## Verification

Define the relevant success check, then verify against actual output or
behavior. Run the project's appropriate tests and linters when the task calls
for them. Report the commands run and their results; do not claim a check that
was not performed. Do not rerun flaky failures without a specific hypothesis.
Run test and direct lint commands as
`bash "$HOME/.codex/hooks/test-lint-run.sh" {test|lint|both} -- <command>` so
the PostToolUse hook can verify their exit status. Use direct linters in the
primary session; lint-agent results do not satisfy the commit gate.

The primary agent alone runs verification commands. Subagents must not run
builds, tests, linters, formatters, type checks, benchmarks, or other project
validation commands. They may inspect files and report which checks the
primary agent should run after integrating their work.

## Build and execution

Follow `~/.codex/memory/execution_hierarchy.md`; prefer VM/container builds
where the project requires them. Keep commands bounded, clean up only
resources created for the task, and never perform broad host cleanup.
Language-specific rules are in `~/.codex/memory/{language}_conventions.md`.

## Subagents

Use custom agents for clearly scoped specialist tasks and read-only agents for
exploration. Give each subagent a bounded task and do not let it commit or
push. Subagents may read, research, and edit only their explicitly assigned
files. They must not run builds, tests, lint or formatting commands, type
checks, benchmarks, or commit-gate commands; stage, commit, or push changes; or
spawn further agents. Only the primary agent that received the user's request
may run project validation and commit workflows, once after integrating the
delegated work. If a check appears useful, subagents report it to the primary
agent instead of running it. See
`~/.codex/memory/agent_usage_conventions.md`.

## Commit workflow

Only the primary agent handles commit preparation, gate execution, commits,
and pushes. Subagents may not perform any part of that workflow. Use
`gitcommit --dir {project_dir} all` as the only commit/push path. Never
read the `gitcommit` executable itself. Before committing, follow
`~/.codex/memory/gitcommit_conventions.md`, ensure the test and lint gates
passed, and document every changed file in `.git/COMMIT_MESS`. After a push,
check the project's CI run and resolve failures before reporting completion.

## Output

Be concise but complete. Lead with the result, use a structured format when
it makes the work easier to review, and avoid filler and reflexive agreement.
You act on the user's behalf; never credit Codex, ChatGPT, OpenAI, another AI
system, or yourself as an author or co-author. Do not add generated-by lines,
AI attribution, or co-author trailers.

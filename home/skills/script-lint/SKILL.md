---
name: script-lint
description: Run ShellCheck on Bash/sh scripts in the current project from the primary session.
---

Run ShellCheck directly on the target scripts through the test/lint gate wrapper:

`bash "$HOME/.codex/hooks/test-lint-run.sh" lint -- shellcheck <script paths>`

The primary session owns lint execution; do not delegate lint commands to a
subagent.

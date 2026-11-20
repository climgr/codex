---
name: script-lint
description: Lint bash/sh scripts in the current project for CasjaysDev convention violations. Invokes the script-lint agent on the project in the current working directory.
---

Run ShellCheck directly on the target scripts through the test/lint gate wrapper:

`bash "$HOME/.codex/hooks/test-lint-run.sh" lint -- shellcheck <script paths>`

The primary session owns lint execution; do not delegate lint commands to a
subagent.

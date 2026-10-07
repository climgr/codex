---
name: go-lint
description: Run the Go lint command in the primary session for the requested project.
---

Run the Go linter directly through the test/lint gate wrapper, using
`golangci-lint run` when available or `go vet ./...` otherwise:

`bash "$HOME/.codex/hooks/test-lint-run.sh" lint -- golangci-lint run`

The primary session owns lint execution; do not delegate lint commands to a
subagent.

---
name: go-lint
description: Lint the current Go project for CasjaysDev convention violations. Invokes the go-lint agent on the project in the current working directory.
---

Run the Go linter directly through the test/lint gate wrapper, using
`golangci-lint run` when available or `go vet ./...` otherwise:

`bash "$HOME/.codex/hooks/test-lint-run.sh" lint -- golangci-lint run`

The primary session owns lint execution; do not delegate lint commands to a
subagent.

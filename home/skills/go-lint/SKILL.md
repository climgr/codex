---
name: go-lint
description: Lint the current Go project for CasjaysDev convention violations. Invokes the go-lint agent on the project in the current working directory.
---

Run Go lint inside the maintained Go toolchain container. Never run Go tools
directly on the host. Create the host cache directories first, then pass the
container command through the test/lint gate wrapper:

```bash
PROJECT_ROOT="$(git rev-parse --show-toplevel)"
PROJECT_NAME="${PROJECT_ROOT##*/}"
GO_CACHE="${GO_CACHE:-$HOME/go/pkg/mod}"
GO_BUILD="${GO_BUILD:-$HOME/.cache/go-build/$PROJECT_NAME}"
mkdir -p "$GO_CACHE" "$GO_BUILD"
bash "$HOME/.codex/hooks/test-lint-run.sh" lint -- \
  docker run --rm \
  --name "$PROJECT_NAME-$(tr -dc 'a-z0-9' </dev/urandom | head -c8)" \
  --memory=4g --cpus=2 \
  -v "$PROJECT_ROOT":/app \
  -v "$GO_CACHE":/usr/local/share/go/pkg/mod \
  -v "$GO_BUILD":/usr/local/share/go/cache \
  -w /app \
  -e CGO_ENABLED=0 \
  -e GOFLAGS=-buildvcs=false \
  casjaysdev/go:latest golangci-lint run
```

If `golangci-lint` is unavailable in the container, replace the final command
with `go vet ./...`; keep it inside the same container invocation.

The primary session owns lint execution; do not delegate lint commands to a
subagent.

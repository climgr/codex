---
name: rust-lint
description: Lint the current Rust project for CasjaysDev convention violations. Invokes the rust-lint agent on the project in the current working directory.
---

Run Clippy directly through the test/lint gate wrapper:

`bash "$HOME/.codex/hooks/test-lint-run.sh" lint -- cargo clippy --all-targets --all-features -- -D warnings`

The primary session owns lint execution; do not delegate lint commands to a
subagent.

---
name: rust-lint
description: Run Clippy in the primary session for the requested Rust project.
---

Run Clippy directly through the test/lint gate wrapper:

`bash "$HOME/.codex/hooks/test-lint-run.sh" lint -- cargo clippy --all-targets --all-features -- -D warnings`

The primary session owns lint execution; do not delegate lint commands to a
subagent.

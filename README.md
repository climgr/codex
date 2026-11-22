# climgr/codex

Codex user configuration maintained by the `climgr` organization. `install.sh` deploys configuration from `home/` into `~/.codex/` and skills into `~/.agents/skills/`.

## Contents

| Path | Purpose |
|------|---------|
| `home/AGENTS.md` | Global Codex instructions |
| `home/config.toml` | User-level Codex settings |
| `home/hooks.json`, `home/hooks/` | Lifecycle hook wiring and scripts; `CODEX_HOOK_BYPASS=1 <command>` skips the read-drift, test/lint, doc-sync, and workflow-validation hooks while unknown hooks remain enforced |
| `home/hooks/classify-test-lint.py` | Classifies test/lint commands inside containers and over SSH to VMs |
| `home/pretool-hook-result.py` | Converts hook denials to Codex responses and applies the explicit Bash hook bypass only to its allowlisted hooks |
| `home/agents/` | Custom agent TOML definitions |
| `home/skills/` | Codex skills installed into `~/.agents/skills/` |
| `home/memory/` | Convention and reference files |
| `home/TEMPLATES/` | Project and feature specifications |
| `install.sh` | Installs configuration into `~/.codex/` and skills into `~/.agents/skills/` |

## Install

Requires Git and the Codex CLI. Review the installer before running it:

```sh
curl -fsSL https://raw.githubusercontent.com/climgr/codex/main/install.sh | sh
```

The installer fast-forwards the local checkout at `~/.local/dotfiles/climgr/codex`, copies Codex configuration into `~/.codex/`, and installs skills from `home/skills/` into `~/.agents/skills/`. Matching files are overwritten while unrelated files are preserved. It does not install or update Codex, modify authentication, or change MCP servers or plugins.

After installation or hook changes, review and trust hook definitions with `/hooks` in Codex.

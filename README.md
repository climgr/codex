# climgr/config

Codex user configuration maintained by the `climgr` organization. The `home/` tree is installed into `~/.codex/` by `install.sh`.

## Contents

| Path | Purpose |
|------|---------|
| `home/AGENTS.md` | Global Codex instructions |
| `home/config.toml` | User-level Codex settings |
| `home/hooks.json`, `home/hooks/` | Lifecycle hook wiring and scripts |
| `home/agents/` | Custom agent TOML definitions |
| `home/skills/` | Codex skills |
| `home/memory/` | Convention and reference files |
| `home/TEMPLATES/` | Project and feature specifications |
| `install.sh` | Installs this configuration into `~/.codex/` |

## Install

Requires Git and the Codex CLI. Review the installer before running it:

```sh
curl -fsSL https://raw.githubusercontent.com/climgr/config/main/install.sh | sh
```

The installer fast-forwards the local checkout at `~/.local/dotfiles/climgr/config` and copies `home/` into `~/.codex/` without deleting unrelated files. It does not install or update Codex, modify authentication, or change MCP servers or plugins.

After installation or hook changes, review and trust hook definitions with `/hooks` in Codex.

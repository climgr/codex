# Project description

`climgr/config` distributes the Codex configuration maintained by this organization. The repository contains user-level instructions, settings, custom agents, skills, lifecycle hooks, memory references, and reusable templates. `install.sh` copies Codex configuration from `home/` into `~/.codex/` and skills into `~/.agents/skills/`.

## Project variables

project_name: config
project_org: climgr
internal_name: config
internal_org: climgr
deploy_target: ~/.codex and ~/.agents/skills
source_dir: home

## Business logic

- `home/` is the version-controlled source for the user-level Codex setup installed in `~/.codex/` and `~/.agents/skills/`.
- `install.sh` clones or fast-forwards `https://github.com/climgr/config`, then copies Codex configuration into `~/.codex/` and skills into `~/.agents/skills/`, overwriting matching files and preserving unrelated files.
- The installer requires Git and the Codex CLI; it does not install/update Codex or alter authentication, MCP servers, or plugins.
- Hook definitions are reviewed and trusted in Codex with `/hooks` after installation or when definitions change.
- Configuration changes should remain valid for Codex and must not rely on Claude-only settings, agent formats, or lifecycle behavior.

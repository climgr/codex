# codexmgr/config — Implementation Spec

This repository is the source for user-level Codex configuration. `home/` mirrors the contents installed into `~/.codex/`; `install.sh` updates that directory additively.

## Repository layout

- `home/AGENTS.md` — global Codex instructions installed to `~/.codex/AGENTS.md`.
- `home/config.toml` — user-level Codex defaults.
- `home/hooks.json` and `home/hooks/` — Codex lifecycle configuration and hook scripts.
- `home/agents/*.toml` — custom Codex agent definitions.
- `home/skills/*/SKILL.md` — Codex skills.
- `home/memory/` — referenced convention files and their index.
- `home/TEMPLATES/` — reusable project and feature specifications.
- `install.sh` — clones or updates `https://github.com/codexmgr/config` and copies `home/` into `~/.codex/`.

## Installer requirements

- Require `git` and the `codex` CLI to be available.
- Store the local checkout at `$HOME/.local/dotfiles/codexmgr/config`.
- Update an existing checkout with a fast-forward-only pull; never discard its local changes.
- Refuse to replace a non-git path at the checkout location.
- Copy `home/.` to `$HOME/.codex/` without deleting unrelated user files.
- Mark installed shell hooks executable.
- Do not update Codex itself, alter Codex authentication, or add/remove MCP servers or plugins.
- Tell the user to review changed hook definitions with `/hooks` in Codex.

## Codex compatibility

All deployed behavior must use Codex-supported formats and paths. Use `AGENTS.md` for instructions, TOML for custom agents and config, `SKILL.md` for skills, and Codex lifecycle events in `hooks.json`. Keep provider-specific behavior out of the configuration unless Codex supports it directly.

## Verification and commit

There is no build step. Before committing changes:

1. Run `sh -n install.sh` and `bash -n` on changed Bash scripts.
2. Run the applicable script lint workflow.
3. Validate `home/config.toml`, all agent TOML files, and `home/hooks.json` with parsers.
4. Update this file and `README.md` when installer behavior or repository contents change.
5. Commit through `gitcommit --dir {project_dir} all` after writing and checking `.git/COMMIT_MESS`.

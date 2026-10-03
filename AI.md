# climgr/codex — Implementation Spec

This repository is the source for user-level Codex configuration and skills. `install.sh` maps configuration from `home/` into `~/.codex/` and skills into `~/.agents/skills/`, overwriting matching files while preserving unrelated files.

## Repository layout

- `home/AGENTS.md` — global Codex instructions installed to `~/.codex/AGENTS.md`.
- `home/config.toml` — user-level Codex defaults.
- `home/hooks.json` and `home/hooks/` — Codex lifecycle configuration and hook scripts.
- `home/agents/*.toml` — custom Codex agent definitions.
- `home/skills/*/SKILL.md` — Codex skills installed to `$HOME/.agents/skills/`.
- `home/memory/` — referenced convention files and their index.
- `home/TEMPLATES/` — reusable project and feature specifications.
- `install.sh` — clones or updates `https://github.com/climgr/codex` and deploys the Codex configuration and skills from `home/` to their user-level locations.

## Installer requirements

- Require `git` and the `codex` CLI to be available.
- Store the local checkout at `$HOME/.local/dotfiles/climgr/codex`.
- Update an existing checkout with a fast-forward-only pull; never discard its local changes.
- Refuse to replace a non-git path at the checkout location.
- Copy the Codex configuration from `home/` to `$HOME/.codex/`, overwriting matching files without deleting unrelated user files.
- Copy `home/skills/` to `$HOME/.agents/skills/`, overwriting matching skills without deleting unrelated user files.
- Mark installed shell hooks executable.
- Do not update Codex itself, alter Codex authentication, or add/remove MCP servers or plugins.
- Tell the user to review changed hook definitions with `/hooks` in Codex.

## Codex compatibility

All deployed behavior must use Codex-supported formats and paths. Use `AGENTS.md` for instructions, TOML for custom agents and config, `SKILL.md` for skills, and Codex lifecycle events in `hooks.json`. Keep provider-specific behavior out of the configuration unless Codex supports it directly.

## Verification and commit

There is no build step. Before committing changes:

1. Run shell syntax checks through `bash "$HOME/.codex/hooks/test-lint-run.sh" test -- <command>` so Codex can verify the exit status; run `bash -n` on changed Bash scripts and `sh -n install.sh` through that wrapper.
2. Run the applicable script lint workflow.
3. Validate `home/config.toml`, all agent TOML files, and `home/hooks.json` with parsers.
4. Update this file and `README.md` when installer behavior or repository contents change.
5. Commit through `gitcommit --dir {project_dir} all` after writing and checking `.git/COMMIT_MESS`.

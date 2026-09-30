---
name: Path resolution conventions
description: provider inference from git remote host, the ~/Projects/local space, and full Local System Management Zone conditions
type: user
---

# Path Resolution Conventions

## Provider Inference

Detect first, infer only as a fallback. Run
`git -C {project_dir} remote get-url origin` and match its host:

- `github.com` → `github`
- `gitlab.com` → `gitlab`
- a host matching the `$GIT_PRIVATE_URL` env var (this machine's own
  self-hosted git instance, e.g. `https://casjay.work`) when it's set →
  `private`
- otherwise match the host against the known Gitea/Forgejo instance for
  `gitea`/`forgejo`

Only when there is no remote at all (or the git-gate check already ruled out
a repo) fall back to inferring `{provider_name}` from the directory name
itself — never guess from the path when a remote is available to check.

## `~/Projects/local`

Not a public-hosting provider — it's this machine's own
multi-repo/system/agent-management space (personal project/infra/fleet
tooling), generally not meant to be public, and may have no remote at all.
It also contains the `local/system/**` zone (below) — that zone's own rules
are unchanged by this section.

## Local System Management Zone (`~/Projects/local/system/**`)

Repos under this exact path are personal project/infra/fleet-management
tooling (managing other repos, servers, systems) — not shippable products.
Only five specific things relax there:

1. Plaintext credentials
2. No required `LICENSE.md`
3. Pre-authorized systemctl lifecycle verbs
4. Cross-repo/host-config access with a recorded grant
5. Raw git commands other than `commit`/`push` bypassing `gitcommit`

Every other rule in `~/.codex/AGENTS.md` and its referenced memory files
stays in full force. Commit and push always go through `gitcommit` — no zone
exception for either, since the user signs every commit and `gitcommit`
handles that signing automatically; a zone repo that must never publish
keeps a `.no_push` file instead.

Full conditions, the exact excluded destructive git commands, the
repo-privacy-gate push sequence, and what never relaxes even in the zone:
`~/.codex/memory/local_system_zone.md`.

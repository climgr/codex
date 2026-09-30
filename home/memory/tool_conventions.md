---
name: Tool conventions
description: Internet access rules, the \command alias-bypass prefix, default flags and usage rules for curl, wget, grep, WebSearch/WebFetch, provider CLIs (gh/glab/tea), act, images, and python3
type: user
---

## General

Always use the right tool for the job if installed: `jq` for JSON, `yq` for YAML, `bc` for math, `grep`/`sed`/`awk` for text, `git` for version control.

Use `python3` only when no purpose-built tool can handle the task cleanly.

## `\command` Prefix

Use the `\command` prefix (`command cmd` in fish) only for alias-prone
external binaries — `ls`, `grep`, `rm`, `cp`, `mv`, `cat`, `sed`, `diff`,
`curl`, and similar. Never use it:

- on shell keywords (`time`, `if`, `while`, `[[`) — breaks semantics
- on builtins — it's a no-op
- on the first word of an allowlisted/pre-authorized or hook-governed command
  (`gitcommit`, `git`, `make`, `docker`, `incus`, `podman`, `qemu-*`,
  `virsh`, `systemctl`) — breaks permission prefix-matching and PreToolUse
  hook pattern-matching; container/VM aliases like `docker`→`podman` are
  deliberate environment config, not noise to bypass

## Internet Access

**AI has internet access and must use it.** Never say "I don't have access to the internet" or refuse to look something up — fetch it.

When to reach for the internet proactively:
- Latest version of a package, library, or tool — always fetch; never guess or use a stale training value
- API docs, man pages, RFCs, or spec pages — fetch the canonical source rather than recalling from training
- A dependency README or changelog — `curl` GitHub/docs directly or use `WebFetch`
- Any fact that changes over time (release dates, CVEs, compatibility matrices, default config values)
- Verifying that a flag, method, or feature actually exists before using it

Tool preference for internet lookups:
- `WebSearch` for open-ended queries (finding the right page)
- `WebFetch` for fetching a known URL (docs page, README, API endpoint)
- `\curl -q -LSs {url}` when piping output into shell tools (`jq`, `grep`, etc.) or saving to a file
- `gh api` / `glab api` / `tea` for provider API operations — never raw `curl` against GitHub/GitLab/Gitea when the CLI is available

**User-provided URLs:** always fetch with `\curl -q -LSs {url}` — never WebFetch. The user gave you a specific URL; use the same tool they would use in a terminal. WebFetch is for AI-initiated lookups only.

## curl

Default: `curl -q -LSs {url}`
- `-q` suppresses config file · `-L` follows redirects · `-S` shows errors · `-s` suppresses progress meter
- Never add `-f`/`--fail` by default — it suppresses the response body on HTTP errors, hiding diagnostic information
- Only add `-f` in scripts or Makefiles where silent failure and a non-zero exit code are explicitly the right behaviour
- Only add `-#` (or drop `-s`) when a progress bar is explicitly needed

## wget

Default: `wget -q {url}` — suppresses all output except errors. Only omit `-q` or add `--show-progress` when a progress bar is explicitly needed.

## grep

Default: always `grep {flags} -- {query}` — `--` prevents a query starting with `-` being treated as a flag.

Never use `egrep`, `fgrep`, or `rgrep` — use `grep -E`, `grep -F`, `grep -r` instead. This applies to every grep invocation, including in Bash tool calls.

## Provider CLIs

Prefer over raw `curl` for provider API operations. If not installed, download and install the binary before use — never fall back to raw `curl` for provider operations when a CLI exists for that provider:

| CLI | License | Purpose | Latest release |
|-----|---------|---------|----------------|
| `gh` | Apache-2.0 | GitHub — issues, PRs, releases, repo ops | `https://github.com/cli/cli/releases/latest` |
| `glab` | MIT | GitLab — same operations | `https://gitlab.com/gitlab-org/cli/-/releases` |
| `tea` | MIT | Gitea and Forgejo (compatible API) | `https://gitea.com/gitea/tea/releases` |

**Auto-install when missing** — detect arch (`uname -m`: `x86_64`→`amd64`, `aarch64`→`arm64`), download the latest Linux binary from the provider's release page, install to `/usr/local/bin` if running as root or `sudo -n true 2>/dev/null` succeeds, otherwise `~/.local/bin`. Always `mkdir -p` the target dir and `chmod +x` after download. Confirm with the user before installing to `/usr/local/bin` via sudo.

`curl` is acceptable when there is a reason: CLI not authenticated/configured, operation is simpler or faster without the CLI, public endpoint that needs no auth, or operation has no CLI equivalent.

## act

`act` (nektos/act, MIT) — validate and run GitHub Actions workflows locally before pushing. Install: `setupmgr act`.

Key uses:
- `act --list -W {file}` — validate a workflow file (parses YAML + resolves job graph, exits non-zero on errors)
- `act -j {job}` — run a specific job locally

**Required pre-commit:** if `.github/workflows/` files are staged, `act --list` must pass on each before `gitcommit` runs — the `validate-workflows.sh` hook enforces this automatically. Never use `act` to bypass CI gates — it is a pre-push verification tool only.

## Images

Always convert before reading — max 1280px longest side, WebP target, fallback chain `convert` → `ffmpeg` → `vips` → original. URL images: curl to tempdir first, then convert, then read. See `image_conventions.md`.

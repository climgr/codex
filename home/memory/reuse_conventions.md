---
name: Reuse-before-creating conventions
description: search-before-write rules for variables/constants, functions, UI components, and host-level system configuration entries
type: user
---

# Reuse Before Creating

Before writing a new function, variable/constant, UI component, or system
configuration entry, search for an existing one that already covers the
need and reuse or extend it. Only create something new when nothing existing
fits.

## Variables/Constants ("search before write")

Before adding a value, enumerate every place it could already live (config
files, env files, code constants, docs — not just the one you thought of
first) and grep each one; only after all are checked and come up empty is
create/append allowed; replace in place if found in any of them.

## Functions

Grep for an existing function with the same or similar behavior (same
package/module, existing helpers/handlers/validators) before writing a new
one; two near-identical functions differing only by a hardcoded value should
be one function taking that value as a parameter.

## UI Components/Styling

Full rules, including the "everything must be styled, reuse existing
classes/tokens before writing new CSS" convention:
`~/.codex/memory/ui_ux_conventions.md`.

## System Configuration Entries (repos, services, jobs, rules)

Before adding or modifying a host-level config entry, search existing
config by the identifying value for that config's type, not by filename
alone:

- **Package-repo definition** (`/etc/yum.repos.d/*.repo`,
  `/etc/apt/sources.list.d/*`) — grep every existing repo file for the
  **URL/hostname** first, since a custom mirror can live under any filename
- **A service like fail2ban** (`/etc/fail2ban/jail.d/*`) — grep by the
  **jail/section name** or **service filename** it targets
- **A systemd unit or cron/timer entry** — check
  `systemctl list-unit-files`/existing crontabs for the **unit name or
  command** before adding a duplicate
- **A firewall rule** — check the live ruleset (see
  `~/.codex/memory/firewall_conventions.md`) for the **port/service name**
  before adding a redundant or conflicting one

Only create a new entry when the search comes up empty; edit the existing
entry in place otherwise.

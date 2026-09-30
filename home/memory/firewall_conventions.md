---
name: Firewall conventions
description: firewalld/ufw auto-detection, default-allow-with-explicit-drops posture, and optional fail2ban-style abuse blocking
type: user
---

# Firewall Conventions

## Backend Detection — firewalld vs ufw

Never hardcode one backend. Detect which is active on the target host before writing or changing any rule:

```sh
if \command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
  FIREWALL_BACKEND="firewalld"
elif \command -v ufw >/dev/null 2>&1 && ufw status | \grep -q "^Status: active"; then
  FIREWALL_BACKEND="ufw"
else
  FIREWALL_BACKEND="none"
fi
```

- **RHEL/Fedora/CentOS family** → `firewalld` is the distro default; use `firewall-cmd`, never disable it in favor of raw `iptables`/`nftables`
- **Debian/Ubuntu family** → `ufw` is the common default; use `ufw`, never disable it in favor of raw `iptables`/`nftables`
- If neither is active (`FIREWALL_BACKEND=none`), that's a finding to report, not something to silently work around — a host with no firewall manager active is a security gap, and enabling one is a decision for the user, not an autonomous action
- Never assume a backend from the distro name alone when detection is possible — a RHEL host can have `ufw` installed instead, and vice versa; the live `is-active`/`status` check above is authoritative, not the distro family guess

## Default Posture: Default-Allow With Explicit Drops

The standard policy for this environment is **default-allow, explicit per-service drops** — not default-deny with an allowlist. The firewall stays enabled and passes traffic through by default; specific services that must never be reachable are explicitly blocked, and abuse-pattern blocking (repeated auth failures, port scans) is handled by a separate tool (see fail2ban section below), not by the firewall's static ruleset.

This is a deliberate choice for this convention, distinct from the tighter default-deny posture some hardening guides recommend — do not "improve" a host by silently flipping it to default-deny; that changes availability behavior and requires the user's decision.

### firewalld — drop SMB example

```sh
firewall-cmd --permanent --remove-service=samba 2>/dev/null || true
firewall-cmd --permanent --add-rich-rule='rule service name="samba" reject'
firewall-cmd --permanent --add-rich-rule='rule port port="139" protocol="tcp" drop'
firewall-cmd --permanent --add-rich-rule='rule port port="445" protocol="tcp" drop'
firewall-cmd --reload
```

### ufw — drop SMB example

```sh
ufw deny 139/tcp
ufw deny 445/tcp
ufw deny 137/udp
ufw deny 138/udp
```

- `deny`/`drop` for services that must never be exposed (SMB/CIFS ports 137-139, 445 is the canonical example — file-sharing protocols with a long history of being targeted from the open internet)
- Everything else stays at the zone/policy default (`public` zone default-allow in firewalld terms, `ufw default allow incoming` — or whatever the host's existing default already is; never flip the zone/global default policy without being asked)
- Document every explicit drop with a comment in the script/playbook that applies it — a bare `deny 445/tcp` with no note forces the next reader to reverse-engineer why

## fail2ban (or Equivalent) — Optional, Not Mandatory

Abuse-based blocking (repeated failed SSH logins, brute-force attempts against exposed services) is handled by `fail2ban` or an equivalent (`sshguard`, `crowdsec`) — **this is a recommended companion pattern, not a required one.** Do not install or enable fail2ban as a side effect of firewall setup work unless the user asks for it; note it as available when relevant instead.

When fail2ban is in use:

- Jails watch service logs (e.g. `sshd`, `nginx-http-auth`) and add temporary bans via the active backend — `firewalld` has a native fail2ban action (`firewallcmd-rich-rules` / `firewallcmd-ipset`), `ufw` is banned via fail2ban's `iptables`-based actions since `ufw` itself is an `iptables`/`nftables` frontend
- Bans are temporary and IP-scoped (`bantime`), separate from the static service drops above — never encode fail2ban's job as permanent firewall rules, and never encode static service drops as fail2ban jails
- `/etc/fail2ban/jail.local` (never edit `jail.conf` directly — it's overwritten on package upgrade) holds host-specific overrides:

```ini
[sshd]
enabled = true
maxretry = 5
bantime = 1h
findtime = 10m
```

- Verify the active backend's jail action is configured correctly for the detected firewall (`banaction = firewallcmd-rich-rules` for firewalld, `banaction = ufw` for ufw) — a mismatched `banaction` silently fails to ban anything

## Verification

After applying any rule change, verify it took effect against the live ruleset, not just the command's exit code:

```sh
# firewalld
firewall-cmd --list-all
firewall-cmd --list-rich-rules

# ufw
ufw status verbose
ufw status numbered
```

A rule added with `--permanent` (firewalld) is inert until `firewall-cmd --reload` — always reload and re-list before considering the change done.

---
name: Networking conventions
description: hostname/domain TLD rules — .internal for private-network names, .local reserved for mDNS/Avahi, .localdomain never used
type: user
---

# Networking Conventions

## Private-Network Domain Suffix

**Use `.internal` for any private/internal-network hostname or domain that should never resolve on public DNS** (internal services, VPN hosts, LAN-only vhosts, container/service names used across hosts). `.internal` is reserved for exactly this by RFC 9476 — it will never collide with a public TLD or a delegated public zone.

**Never use `.local`** for these names — it is reserved for mDNS/Avahi/Bonjour link-local resolution (RFC 6762). A non-mDNS host or service named `*.local` risks resolver conflicts with real mDNS traffic on the same network, and some resolvers (systemd-resolved, nss-mdns) special-case or refuse to forward it.

**Never use `.localdomain`** — it is only the legacy default domain some Linux installers/`hostnamectl` set when no domain is configured. It carries no IANA/RFC reservation and no real meaning; treat any existing `.localdomain` name as a leftover default to rename, not a convention to continue.

## Exception — mDNS/Avahi

`.local` is required, not optional, when the name is actually resolved via mDNS (Avahi on Linux, Bonjour on macOS/iOS, or any zero-config LAN discovery flow) — e.g. `printer.local`, a device advertising itself over Avahi, or a service explicitly discovered through `avahi-browse`/`dns-sd`. In that case `.local` is the correct and only working suffix; do not substitute `.internal`, since mDNS resolution only triggers on the `.local` TLD.

## Applying This

- New hostnames/domains for internal services, reverse-proxy vhosts (see `nginx_conventions.md`), Docker/Compose service names shared across hosts, VPN/mesh peers, internal API endpoints: `*.internal`
- Existing `*.local` or `*.localdomain` names found during unrelated work: flag them (log in `TODO.AI.md` per the "no issue left only in conversation" rule) rather than silently renaming — a live hostname rename can break running config, DNS records, or TLS certs issued for the old name
- Public-facing domains are unaffected — this rule only concerns names that must never be publicly resolvable

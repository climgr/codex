#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202609170001-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  protect-host.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Friday, May 01, 2026 10:22 EDT
# @@File             :  protect-host.sh
# @@Description      :  Codex PreToolUse hook - block truly destructive Bash ops on host
# @@Changelog        :  Rule 5 redirect check now reads the command over stdin and blocks only on a printed match — a very long command line exceeded the kernel argv limit, python3 failed to launch, and the non-zero status was misread as a match, blocking harmless calls. Synced VERSION with the header.
# @@TODO             :  See project issues
# @@Other            :  Container-mediated commands (docker/incus/podman/kubectl exec) are exempted
# @@Resource         :  Codex lifecycle hooks
# @@Terminal App     :  no
# @@sudo/root        :  no
# @@Template         :  shell/bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC1001,SC1003,SC2001,SC2003,SC2016,SC2031,SC2090,SC2115,SC2120,SC2155,SC2199,SC2229,SC2317,SC2329
# - - - - - - - - - - - - - - - - - - - - - - - - -
VERSION="202609170001-git"
# - - - - - - - - - - - - - - - - - - - - - - - - -
set -uo pipefail
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Protection philosophy: surgical, not broad.
#
# ALWAYS blocked (true non-exemptables):
#   • Delete/corrupt auth-critical files: /etc/passwd, /etc/shadow, /etc/group,
#     /etc/gshadow, /etc/sudoers, /etc/master.passwd
#   • Write arbitrary files into core OS binary dirs: /bin/, /sbin/, /usr/bin/, /usr/sbin/
#   • Wipe filesystem root (/) or home directory itself (rm -rf ~)
#   • Wipe a top-level system dir itself or its contents (rm -rf /etc, rm -rf /etc/*)
#   • Raw block-device writes (dd/mkfs to /dev/sd*, /dev/nvme*)
#   • pkill/killall (name-based process kill — hits unrelated host processes)
#   • Unscoped container/instance sweeps (unfiltered docker ps or incus list feeding kill/stop/rm/delete; docker prune)
#   • systemctl host-service mutation (restart/stop/start/etc. without --user)
#
# ALLOWED (legitimate sysadmin — not blocked):
#   • chmod/chown/chgrp on any path (e.g. chmod 700 /etc/wireguard)
#   • mkdir/cp/mv/install/ln to /etc/*, /var/*, /opt/*, /run/*, /usr/local/*, etc.
#   • Shell redirects to config files (e.g. > /etc/wireguard/wg0.conf)
#   • tee, wg genkey, and similar pipe-based generators writing to system config paths
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Core OS binary dirs — arbitrary writes here = code execution risk.
PROTECT_HOST_CORE_BINARY='(/bin|/sbin|/usr/bin|/usr/sbin)'
# Auth-critical files — deleting or overwriting breaks authentication/identity.
PROTECT_HOST_AUTH_CRITICAL='(/etc/(passwd|shadow|gshadow|group|sudoers|master\.passwd))'
# Home-directory root only — the home dir ITSELF, not subpaths.
# Derived from $HOME at runtime — never hardcode /home/<user> paths.
# The expanded path, the unexpanded $HOME spelling, and ~ are equivalent targets.
PROTECT_HOST_HOME_PATH="$(printf '%s' "${HOME:-/root}" | \sed 's/[].^$*+?(){}|\\[]/\\&/g')"
PROTECT_HOST_HOME_LITERAL="(${PROTECT_HOST_HOME_PATH}|~|\\\$HOME)"
# Truly destructive verbs: delete and wipe only. chmod/chown are NOT here — they configure, not destroy.
PROTECT_HOST_DESTRUCTIVE_VERBS='rm|rmd|rmdir|shred|truncate|wipefs'
# Write verbs that install/overwrite files.
PROTECT_HOST_WRITE_VERBS='mv|cp|install|ln'
# Container/VM-mediated command prefixes — anything running INSIDE a container or
# test VM is exempt from every rule (the blast radius is the disposable guest, not
# the host). Newline-separated; consumed by both python helpers via the environment
# so the two lists can never drift apart. Entries ending in "-" match as-is
# (qemu-system-x86_64 etc.); all others get a trailing space for word-boundary safety.
PROTECT_HOST_CONTAINER_PREFIXES="docker exec
docker run
docker container exec
docker container run
docker compose exec
docker compose run
docker-compose exec
docker-compose run
podman exec
podman run
podman container exec
podman container run
podman compose exec
podman compose run
podman-compose exec
podman-compose run
incus exec
incus shell
incus file push
incus file pull
lxc exec
lxc shell
lxc file push
lxc file pull
kubectl exec
kubectl debug
machinectl shell
systemd-nspawn
vagrant ssh
multipass exec
multipass shell
distrobox enter
toolbox run
qemu-system-"
export PROTECT_HOST_CONTAINER_PREFIXES
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Helpers
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# __require_cmd <name> - bail with a clear error if a required tool is missing.
# A broken hook exits 0 (no-op) so we never silently block every Bash call.
__require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'protect-host.sh: required command not found: %s\n' "$1" >&2
    exit 0
  fi
}
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# __extract_command - read the JSON payload on stdin, print tool_input.command.
__extract_command() {
  python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get("tool_input", {}).get("command", ""))
except Exception:
    print("")
'
}
# __extract_cwd - read the JSON payload on stdin, print the hook cwd field.
__extract_cwd() {
  python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get("cwd", ""))
except Exception:
    print("")
'
}
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# __strip_heredoc_bodies - remove heredoc BODY lines before scanning, but only when
# the heredoc feeds a non-shell command (python3, cat, tee, jq, ...). Body text fed
# to bash/sh/zsh/dash/ksh/ash IS executable shell and stays fully scanned - no bypass
# through the shell itself - UNLESS the shell is container/VM-mediated (docker exec,
# incus exec, ...): those bodies execute inside the disposable guest and are exempt. Rationale: a python/cat heredoc that merely MENTIONS
# "rm -rf /" is data, not a command, and blocking it is a false positive. A deliberate
# evasion via python (os.system etc.) never matched these shell-shaped regexes anyway;
# this hook is an accident guardrail, not a security boundary. On any parse error the
# original text is emitted unchanged so scanning never silently weakens.
__strip_heredoc_bodies() {
  python3 -c '
import os, re, sys
text = sys.stdin.read()
try:
    shells = {"bash", "sh", "zsh", "dash", "ksh", "ash"}
    raw_prefixes = [
        p for p in os.environ.get("PROTECT_HOST_CONTAINER_PREFIXES", "").splitlines()
        if p.strip()
    ]
    # Same flag/sudo/whitespace-tolerant matcher as __strip_container_subcmds -
    # "incus -q exec c bash <<EOF" and "sudo docker exec -i c bash <<EOF" are
    # container-mediated heredocs too, not just the exact literal prefix form.
    patterns = []
    for p in raw_prefixes:
        if p.endswith("-"):
            patterns.append(re.compile(r"^" + re.escape(p)))
            continue
        words = p.split(" ")
        binary, rest = words[0], " ".join(words[1:])
        patterns.append(re.compile(
            r"^" + re.escape(binary) + r"(?:\s+-{1,2}\S+)*\s+"
            + re.escape(rest) + r"(?:\s|$)"
        ))
    out = []
    lines = text.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        delims = []
        for m in re.finditer(r"(?<!<)<<(?!<)-?\s*([\x27\"]?)(\w+)\1", line):
            head = line[: m.start()]
            tokens = {t.lstrip("\\\\") for t in head.split()}
            # container/VM-mediated heredocs are exempt even when fed to a shell:
            # "docker exec -i c bash <<EOF" runs the body inside the guest
            probe = re.sub(
                r"^\s*(?:\\\\|(?:command|builtin|env)\s+|exec\s+|sudo(?:\s+-\S+)*\s+)+",
                "", head.strip()
            )
            probe = re.sub(r"\s+", " ", probe).strip()
            if any(pat.match(probe) for pat in patterns) or not (tokens & shells):
                delims.append(m.group(2))
        i += 1
        for delim in delims:
            while i < len(lines):
                if lines[i].strip() == delim:
                    out.append(lines[i])
                    i += 1
                    break
                i += 1
    print("\n".join(out))
except Exception:
    print(text)
'
}
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# __strip_container_subcmds - split the command on newlines and shell separators,
# drop sub-commands that run inside a container/sandbox, print the rest one per line.
# Splitting is intentionally naive (quoted separators over-split) — over-splitting
# only makes the check stricter, never looser. Exempting per sub-command closes the
# old whole-command-prefix bypass: "docker run --rm img true; rm -rf ~" no longer
# gets a free pass just because the string STARTS with "docker run ".
__strip_container_subcmds() {
  python3 -c '
import os, re, sys
cmd = sys.stdin.read()
raw_prefixes = [
    p for p in os.environ.get("PROTECT_HOST_CONTAINER_PREFIXES", "").splitlines()
    if p.strip()
]
# Build a matcher per prefix: exact dash-suffixed prefixes (qemu-system-) match
# as-is; "binary sub words" prefixes allow short flags (-q, --project) between
# the binary and its sub-command so "incus -q exec" still counts as incus exec.
patterns = []
for p in raw_prefixes:
    if p.endswith("-"):
        patterns.append(re.compile(r"^" + re.escape(p)))
        continue
    words = p.split(" ")
    binary, rest = words[0], " ".join(words[1:])
    patterns.append(re.compile(
        r"^" + re.escape(binary) + r"(?:\s+-{1,2}\S+)*\s+"
        + re.escape(rest) + r"(?:\s|$)"
    ))
kept = []
for part in re.split(r"[\n;]|&&|\|\||[|&]", cmd):
    sub = part.strip()
    if not sub:
        continue
    # normalize house-style alias-safe backslashes, command/env/exec/sudo
    # wrappers (sudo may carry its own flags, e.g. "sudo -u root") for the
    # exemption check only — \docker exec, command docker exec, and
    # sudo incus exec are still container-mediated; the original sub is
    # what gets kept and scanned. Collapse repeated whitespace too, so
    # "incus  exec" (double space) still matches "incus exec".
    probe = re.sub(
        r"^(?:\\|(?:command|builtin|env)\s+|exec\s+|sudo(?:\s+-\S+)*\s+)+", "", sub
    )
    probe = re.sub(r"\s+", " ", probe).strip()
    if any(pat.match(probe) for pat in patterns):
        continue
    kept.append(sub)
print("\n".join(kept))
'
}
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# __block <reason> - emit a structured BLOCKED message and exit 2.
# AI.md Part 6's blocking-output format writes the reason to both streams:
# stderr so Codex feeds it back as the block reason, stdout so the
# same text is also captured in the session transcript.
__block() {
  printf 'BLOCKED: %s\n' "$1"
  printf 'BLOCKED: %s\n' "$1" >&2
  exit 2
}
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# __match <regex> - return 0 if "$PROTECT_HOST_CMD" matches the extended regex.
__match() {
  printf '%s' "$PROTECT_HOST_CMD" | \grep -qE -- "$1"
}
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
__require_cmd python3
__require_cmd grep
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# $(cat) is required here — hook stdin is a socket; $(</dev/stdin) re-opens it and fails with ENXIO
PROTECT_HOST_INPUT="$(cat)"
PROTECT_HOST_CMD="$(printf '%s' "$PROTECT_HOST_INPUT" | __extract_command)"
# Local System Management Zone (~/Projects/local/system/**, see AGENTS.md) pre-authorizes
# a subset of systemctl lifecycle commands. Derived from $HOME at runtime — never hardcode.
PROTECT_HOST_ZONE_ROOT="${HOME:-/root}/Projects/local/system"
PROTECT_HOST_CWD="$(printf '%s' "$PROTECT_HOST_INPUT" | __extract_cwd)"
PROTECT_HOST_IN_ZONE=0
case "$PROTECT_HOST_CWD" in
  "$PROTECT_HOST_ZONE_ROOT" | "$PROTECT_HOST_ZONE_ROOT"/*) PROTECT_HOST_IN_ZONE=1 ;;
esac
# Non-shell heredoc bodies are data, not commands — drop them before any rule sees
# the text so a python/cat heredoc mentioning "rm -rf /" is not a false positive.
PROTECT_HOST_CMD="$(printf '%s' "$PROTECT_HOST_CMD" | __strip_heredoc_bodies)"
# Raw command kept for pipeline-shaped rules — sub-command splitting severs
# pipes, so "docker ps -q | xargs docker kill" is only visible here.
PROTECT_HOST_RAW_CMD="$PROTECT_HOST_CMD"
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Empty / non-Bash payload - nothing to inspect.
[ -z "$PROTECT_HOST_CMD" ] && exit 0
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Container-mediated sub-commands are explicitly trusted at this layer;
# everything else in a compound/multi-line command is still inspected.
PROTECT_HOST_CMD="$(printf '%s' "$PROTECT_HOST_CMD" | __strip_container_subcmds)"
[ -z "$PROTECT_HOST_CMD" ] && exit 0
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Word-boundary fragment reused across rules.
# Includes backslash so the house-style alias bypass "\rm" is still caught.
PROTECT_HOST_WORD_START='(^|[[:space:];|&`(\])'
# Up to 32 non-flag, non-operator tokens between a verb and its target path.
PROTECT_HOST_TOKEN_GAP='([[:space:]]+[^[:space:]&|;()`<>]+){0,32}'
# Path tails — match the root itself OR any subpath beneath it.
PROTECT_HOST_CORE_BINARY_TAIL="${PROTECT_HOST_CORE_BINARY}([[:space:]/]|\$)"
PROTECT_HOST_AUTH_CRITICAL_TAIL="${PROTECT_HOST_AUTH_CRITICAL}([[:space:]]|\$)"
# Trailing /* (wipe-the-contents form) is as destructive as the dir itself.
PROTECT_HOST_HOME_TAIL="${PROTECT_HOST_HOME_LITERAL}(/\*?)?([[:space:]]|\$)"
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Rule 1: destructive verb on auth-critical files.
if __match "${PROTECT_HOST_WORD_START}(${PROTECT_HOST_DESTRUCTIVE_VERBS})${PROTECT_HOST_TOKEN_GAP}[[:space:]]+${PROTECT_HOST_AUTH_CRITICAL_TAIL}"; then
  __block "destructive op on auth-critical file (/etc/passwd, /etc/shadow, /etc/group, etc.)"
fi
# Rule 2: destructive verb on core OS binary dirs.
if __match "${PROTECT_HOST_WORD_START}(${PROTECT_HOST_DESTRUCTIVE_VERBS})${PROTECT_HOST_TOKEN_GAP}[[:space:]]+${PROTECT_HOST_CORE_BINARY_TAIL}"; then
  __block "destructive op on core OS binary path (/bin, /sbin, /usr/bin, /usr/sbin) — use a package manager"
fi
# Rule 3: destructive verb on the home directory root itself (not subpaths).
if __match "${PROTECT_HOST_WORD_START}(${PROTECT_HOST_DESTRUCTIVE_VERBS})${PROTECT_HOST_TOKEN_GAP}[[:space:]]+${PROTECT_HOST_HOME_TAIL}"; then
  __block "destructive command targeting the home directory itself"
fi
# Rule 4: destructive verb on the filesystem root / (including the /* contents form).
if __match "${PROTECT_HOST_WORD_START}(${PROTECT_HOST_DESTRUCTIVE_VERBS})${PROTECT_HOST_TOKEN_GAP}[[:space:]]+/\*?([[:space:]]|\$)"; then
  __block "destructive op targeting the filesystem root /"
fi
# Rule 4b: destructive verb on a top-level system dir ITSELF or its /* contents glob.
# Scoped deletes beneath them (rm -rf /etc/wireguard, rm -rf /var/tmp/build) stay allowed.
PROTECT_HOST_SYSTEM_DIRS='(/bin|/boot|/dev|/etc|/lib|/lib32|/lib64|/opt|/proc|/run|/sbin|/srv|/sys|/usr|/var)'
if __match "${PROTECT_HOST_WORD_START}(${PROTECT_HOST_DESTRUCTIVE_VERBS})${PROTECT_HOST_TOKEN_GAP}[[:space:]]+${PROTECT_HOST_SYSTEM_DIRS}(/\*?)?([[:space:]]|\$)"; then
  __block "destructive op targeting a top-level system directory (/etc, /usr, /var, ...) itself"
fi
# Rule 4c: destructive verb on ANY subpath beneath /boot, /dev, /proc, /sys —
# kernel/boot/device paths (home/AGENTS.md's Core OS paths floor: /boot/**,
# /sys/**, /proc/**, /dev/**). Unlike /etc, /var, etc., a scoped delete
# beneath these is never legitimate sysadmin work, so the whole subtree is
# blocked, not just the dir itself or its top-level /* glob.
PROTECT_HOST_KERNEL_DIRS='(/boot|/dev|/proc|/sys)'
if __match "${PROTECT_HOST_WORD_START}(${PROTECT_HOST_DESTRUCTIVE_VERBS})${PROTECT_HOST_TOKEN_GAP}[[:space:]]+${PROTECT_HOST_KERNEL_DIRS}/[^[:space:]]+"; then
  __block "destructive op targeting a subpath under /boot, /dev, /proc, or /sys — kernel/boot/device paths are never a valid target, even scoped"
fi
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Rule 5: shell redirect (> or >>) to auth-critical files or core binary paths.
# /dev/null, /dev/std{in,out,err}, /dev/tty, /dev/fd/N, /dev/pts/N are always safe.
# The command travels over stdin, never argv: a very long command line would
# exceed the kernel's per-argument limit, python3 would fail to launch, and the
# non-zero status would read as a match — blocking the call for no reason.
# A match prints the offending target and exits 0; the caller blocks only on
# non-empty output, so any interpreter failure is silent and fails open.
__check_redirects() {
  printf '%s' "$1" | python3 -c '
import re, sys
# Any unexpected exception must fail OPEN (exit 0) — the documented design is
# that a broken hook never blocks every Bash call; only a real match prints.
sys.excepthook = lambda *a: sys.exit(0)
cmd = sys.stdin.buffer.read().decode("utf-8", "replace")
auth_critical = re.compile(
    r"^/etc/(passwd|shadow|gshadow|group|sudoers|master\.passwd)$"
)
core_binary = re.compile(
    r"^/(bin|sbin|usr/bin|usr/sbin)(/|$)"
)
safe_pseudo = re.compile(
    r"^/dev/(null|stdin|stdout|stderr|tty|fd/\d+|pts/\d+)$"
)
for m in re.finditer(r"(?:^|[\s;|&`(])(?:\d+|&)?>>?\s*([^\s;|&`()<>]+)", cmd):
    target = m.group(1).strip(chr(34) + chr(39))
    if safe_pseudo.match(target):
        continue
    if auth_critical.match(target) or core_binary.match(target):
        print(target)
        break
sys.exit(0)
' 2>/dev/null || :
}
PROTECT_HOST_BAD_REDIRECT="$(__check_redirects "$PROTECT_HOST_CMD")"
if [[ -n "$PROTECT_HOST_BAD_REDIRECT" ]]; then
  __block "shell redirect to protected path: $PROTECT_HOST_BAD_REDIRECT"
fi
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Rule 6: find -delete or -exec rm in core OS binary paths or on home dir root.
if __match "${PROTECT_HOST_WORD_START}find[[:space:]]+${PROTECT_HOST_CORE_BINARY}([[:space:]/].*-delete|.*-exec[[:space:]]+rm)"; then
  __block "'find -delete' / '-exec rm' in core OS binary path"
fi
if __match "${PROTECT_HOST_WORD_START}find[[:space:]]+${PROTECT_HOST_HOME_LITERAL}/?[[:space:]]+([^&;|]*-delete|[^&;|]*-exec[[:space:]]+rm)"; then
  __block "'find -delete' / '-exec rm' targeting the home directory itself"
fi
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Rule 7: write-verb (mv/cp/install/ln) to auth-critical files or core OS binary dirs.
# Writes to /etc/*, /var/*, /opt/*, /run/*, /usr/local/*, etc. are allowed.
if __match "${PROTECT_HOST_WORD_START}(${PROTECT_HOST_WRITE_VERBS})${PROTECT_HOST_TOKEN_GAP}[[:space:]]+${PROTECT_HOST_AUTH_CRITICAL_TAIL}"; then
  __block "mv/cp/install/ln to auth-critical file (/etc/passwd, /etc/shadow, /etc/group, etc.)"
fi
if __match "${PROTECT_HOST_WORD_START}(${PROTECT_HOST_WRITE_VERBS})${PROTECT_HOST_TOKEN_GAP}[[:space:]]+${PROTECT_HOST_CORE_BINARY_TAIL}"; then
  __block "mv/cp/install/ln to core OS binary path — install to /usr/local/bin instead"
fi
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Rule 8: raw block-device writers targeting host disks.
if __match "${PROTECT_HOST_WORD_START}(dd|mkfs[^[:space:]]*)[[:space:]].*((of|of=)/dev/|[[:space:]]/dev/[sh]d|[[:space:]]/dev/nvme)"; then
  __block "raw disk writer targeting host device"
fi
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Rule 8b: partition table / bootloader mutation — irreversible boot-critical ops.
if __match "${PROTECT_HOST_WORD_START}(sgdisk|parted|fdisk|cfdisk|gdisk|grub-install|grub2-install)${PROTECT_HOST_TOKEN_GAP}[[:space:]]"; then
  __block "partition-table/bootloader-install command — irreversible, always blocked"
fi
if __match "${PROTECT_HOST_WORD_START}(${PROTECT_HOST_WRITE_VERBS}|${PROTECT_HOST_DESTRUCTIVE_VERBS})${PROTECT_HOST_TOKEN_GAP}[[:space:]]+/etc/default/grub([[:space:]]|\$)"; then
  __block "write/destructive op targeting bootloader config (/etc/default/grub)"
fi
if __match "(^|[[:space:];|&\`(])[0-9]?>>?[[:space:]]*[\"']?/etc/default/grub([[:space:]\"']|\$)"; then
  __block "shell redirect to bootloader config (/etc/default/grub)"
fi
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Rule 9: pkill/killall/kill-by-pgrep — process termination must use tracked PIDs.
if __match "${PROTECT_HOST_WORD_START}(pkill|killall)[[:space:]]"; then
  __block "pkill/killall targets processes by name — use kill \$TRACKED_PID (a PID captured at launch) instead"
fi
if __match "${PROTECT_HOST_WORD_START}kill[[:space:]]+.*\$\(pgrep"; then
  __block "kill \$(pgrep ...) targets processes by pattern — use kill \$TRACKED_PID (a PID captured at launch) instead"
fi
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Rule 10: systemctl host-service mutation requires user confirmation.
# status/is-active/is-enabled/cat/show and --user variants are always safe.
# Local System Management Zone exception: under ~/Projects/local/system/**, the
# lifecycle subset (excluding mask/unmask/isolate/kill) is pre-authorized (see AGENTS.md).
# Container/VM runtime daemon exception: docker/containerd/incus/lxd/libvirtd/
# virtlogd/virtlockd/virtnetworkd/virtstoraged/virtqemud/podman lifecycle is the
# same execution tier as the already-exempted exec/run commands (the engine is
# infrastructure, not a host application service), so it never requires
# confirmation, in or out of the zone.
PROTECT_HOST_SYSTEMCTL_READONLY="${PROTECT_HOST_WORD_START}systemctl[[:space:]]+(status|is-active|is-enabled|cat|show"
PROTECT_HOST_SYSTEMCTL_READONLY="${PROTECT_HOST_SYSTEMCTL_READONLY}|list-units|list-unit-files|list-sockets|list-timers|help)([[:space:]]|\$)"
PROTECT_HOST_SYSTEMCTL_ZONE_LIFECYCLE="${PROTECT_HOST_WORD_START}systemctl[[:space:]]+(restart|stop|start|reload|reload-or-restart"
PROTECT_HOST_SYSTEMCTL_ZONE_LIFECYCLE="${PROTECT_HOST_SYSTEMCTL_ZONE_LIFECYCLE}|try-restart|disable|enable|reset-failed|daemon-reload)([[:space:]]|\$)"
PROTECT_HOST_SYSTEMCTL_RUNTIME_NAMES="(docker(\.socket)?|containerd|incus(\.socket)?|lxd(\.socket)?"
PROTECT_HOST_SYSTEMCTL_RUNTIME_NAMES="${PROTECT_HOST_SYSTEMCTL_RUNTIME_NAMES}|libvirtd(\.socket)?|virtlogd|virtlockd|virtnetworkd|virtstoraged|virtqemud"
PROTECT_HOST_SYSTEMCTL_RUNTIME_NAMES="${PROTECT_HOST_SYSTEMCTL_RUNTIME_NAMES}|podman(\.socket)?)"
PROTECT_HOST_SYSTEMCTL_RUNTIME="${PROTECT_HOST_WORD_START}systemctl[[:space:]]+(restart|stop|start|reload|reload-or-restart"
PROTECT_HOST_SYSTEMCTL_RUNTIME="${PROTECT_HOST_SYSTEMCTL_RUNTIME}|try-restart|enable|disable|"
PROTECT_HOST_SYSTEMCTL_RUNTIME="${PROTECT_HOST_SYSTEMCTL_RUNTIME}reset-failed|daemon-reload)[[:space:]]+"
PROTECT_HOST_SYSTEMCTL_RUNTIME="${PROTECT_HOST_SYSTEMCTL_RUNTIME}${PROTECT_HOST_SYSTEMCTL_RUNTIME_NAMES}([[:space:]]|\$)"
PROTECT_HOST_SYSTEMCTL_MUTATION="${PROTECT_HOST_WORD_START}systemctl[[:space:]]+(restart|stop|start|reload|reload-or-restart|try-restart"
PROTECT_HOST_SYSTEMCTL_MUTATION="${PROTECT_HOST_SYSTEMCTL_MUTATION}|disable|enable|mask|unmask|isolate|kill|reset-failed|daemon-reload|edit|set-property)([[:space:]]|\$)"
if __match "${PROTECT_HOST_WORD_START}systemctl[[:space:]]"; then
  if __match "${PROTECT_HOST_WORD_START}systemctl[[:space:]]+--user[[:space:]]"; then
    # user-scoped — always OK
    :
  elif __match "$PROTECT_HOST_SYSTEMCTL_READONLY"; then
    # read-only — always OK
    :
  elif [ "$PROTECT_HOST_IN_ZONE" = 1 ] && __match "$PROTECT_HOST_SYSTEMCTL_ZONE_LIFECYCLE"; then
    # zone-scoped lifecycle command — pre-authorized, no confirmation needed
    :
  elif __match "$PROTECT_HOST_SYSTEMCTL_RUNTIME"; then
    # container/VM runtime daemon lifecycle — same tier as exec/run, no confirmation needed
    :
  elif __match "$PROTECT_HOST_SYSTEMCTL_MUTATION"; then
    __block "systemctl host-service mutation requires user confirmation — run manually after approval"
  fi
fi
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Rule 11: unscoped container sweeps — the container analog of pkill.
# Feeding an unfiltered `docker ps` list into kill/stop/rm/restart hits EVERY
# container on the host, not just this project's. A name=/label=/--filter scope
# makes the sweep targeted and is allowed. Matched against PROTECT_HOST_RAW_CMD because the
# sub-command split severs pipes.
PROTECT_HOST_CONTAINER_SWEEP_VERBS='(kill|stop|rm|restart)'
PROTECT_HOST_CONTAINER_LIST='(docker|podman)[[:space:]]+(container[[:space:]]+)?(ps|ls)'
# __match_raw <regex> - return 0 if "$PROTECT_HOST_RAW_CMD" matches the extended regex.
__match_raw() {
  printf '%s' "$PROTECT_HOST_RAW_CMD" | \grep -qE -- "$1"
}
if __match_raw "${PROTECT_HOST_WORD_START}(docker|podman)[[:space:]]+${PROTECT_HOST_CONTAINER_SWEEP_VERBS}[^;&]*[\$\`]\(?${PROTECT_HOST_CONTAINER_LIST}" ||
  __match_raw "${PROTECT_HOST_CONTAINER_LIST}[^|]*\|.*(docker|podman)[[:space:]]+${PROTECT_HOST_CONTAINER_SWEEP_VERBS}"; then
  # Scope the filter check to the ps/ls segment itself, not the whole raw
  # command — otherwise an unrelated name=/label= substring elsewhere in the
  # pipeline (e.g. inside the kill/stop/rm target list) falsely satisfies it.
  PROTECT_HOST_CONTAINER_LIST_SEG=$(printf '%s' "$PROTECT_HOST_RAW_CMD" | \grep -oE -- "${PROTECT_HOST_CONTAINER_LIST}[^;&|]*" | head -n 1)
  if ! printf '%s' "$PROTECT_HOST_CONTAINER_LIST_SEG" | \grep -qE -- '(--filter|name=|label=)'; then
    __block "unscoped container sweep — an unfiltered 'docker ps' feeding kill/stop/rm hits EVERY container on the host; \
target project containers by name or add --filter name={project_name}-"
  fi
fi
# Incus/LXC analog: an unfiltered `incus list` feeding stop/delete/restart hits
# EVERY instance on the host. A name= filter, positional name=… key filter, or
# --project scope makes it targeted and is allowed.
PROTECT_HOST_INCUS_SWEEP_VERBS='(stop|delete|rm|restart|pause)'
PROTECT_HOST_INCUS_LIST='(incus|lxc)[[:space:]]+(list|ls)'
if __match_raw "${PROTECT_HOST_WORD_START}(incus|lxc)[[:space:]]+${PROTECT_HOST_INCUS_SWEEP_VERBS}[^;&]*[\$\`]\(?${PROTECT_HOST_INCUS_LIST}" ||
  __match_raw "${PROTECT_HOST_INCUS_LIST}[^|]*\|.*(incus|lxc)[[:space:]]+${PROTECT_HOST_INCUS_SWEEP_VERBS}"; then
  # Scoped to the list segment itself — same rationale as the docker/podman check above.
  PROTECT_HOST_INCUS_LIST_SEG=$(printf '%s' "$PROTECT_HOST_RAW_CMD" | \grep -oE -- "${PROTECT_HOST_INCUS_LIST}[^;&|]*" | head -n 1)
  if ! printf '%s' "$PROTECT_HOST_INCUS_LIST_SEG" | \grep -qE -- '(--filter|name=|label=|--project)'; then
    __block "unscoped instance sweep — an unfiltered 'incus list' feeding stop/delete hits EVERY instance on the host; \
target project instances by name or add a name={project_name}- filter"
  fi
fi
# prune subcommands are always a broad sweep — cleanup must target project resources by name.
if __match_raw "${PROTECT_HOST_WORD_START}(docker|podman)[[:space:]]+(system|builder|buildx|container|image|volume|network)[[:space:]]+prune"; then
  __block "docker prune is a broad sweep — remove only project-scoped resources by name (docker stop/rm {project_name}-XXXX)"
fi
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
exit 0

#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202610120002-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  no-destructive-bypass.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Sunday, August 30, 2026 17:00 EDT
# @@File             :  no-destructive-bypass.sh
# @@Description      :  PreToolUse hook: hard-blocks host and SSH destructive operations, including alias/wrapper-bypass invocations.
# @@Changelog        :  Decode the stdin payload file as UTF-8 with replacement and fail open on any parse exception (not only JSONDecodeError) — a non-UTF-8 byte previously raised UnicodeDecodeError and surfaced as a hook error.
# @@TODO             :  None
# @@Other              :  Explicit SSH and recognized guest payloads are outside the local-host denial; local host commands remain checked.
# @@Resource         :  home/config.toml no-destructive-bypass.sh
# @@Terminal App     :  no
# @@sudo/root        :  no
# @@Template         :  shell/bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC1001,SC1003,SC2001,SC2003,SC2016,SC2031,SC2090,SC2115,SC2120,SC2155,SC2199,SC2229,SC2317,SC2329
# - - - - - - - - - - - - - - - - - - - - - - - - -
VERSION="202610120002-git"
# - - - - - - - - - - - - - - - - - - - - - - - - -
set -euo pipefail

# A broken hook must fail OPEN (exit 0) so it never silently blocks every Bash call.
if ! command -v python3 >/dev/null 2>&1; then
  printf 'no-destructive-bypass.sh: required command not found: python3 (hook disabled, failing open)\n' >&2
  exit 0
fi

NO_DESTRUCTIVE_BYPASS_INPUT="$(cat)"

NO_DESTRUCTIVE_BYPASS_INPUT_TMPFILE="$(mktemp)"
trap 'rm -f "$NO_DESTRUCTIVE_BYPASS_INPUT_TMPFILE"' EXIT
printf '%s' "$NO_DESTRUCTIVE_BYPASS_INPUT" > "$NO_DESTRUCTIVE_BYPASS_INPUT_TMPFILE"

python3 - "$NO_DESTRUCTIVE_BYPASS_INPUT_TMPFILE" <<'PYEOF'
import json
import os
import re
import shlex
import sys

with open(sys.argv[1], "r", encoding="utf-8", errors="replace") as _f:
    raw = _f.read()
try:
    payload = json.loads(raw, strict=False)
except Exception:
    sys.exit(0)

# A JSON scalar or array parses cleanly but has no .get(), so the block
# below would raise AttributeError and exit non-zero. Part 6 requires a
# hook to fail open on any unusable payload, never to surface an error.
if not isinstance(payload, dict):
    sys.exit(0)

# Same reasoning one level down: normalise a non-object tool_input /
# tool_response to an empty dict so every downstream .get() chain below
# stays safe without each call site needing its own type check.
for _field in ("tool_input", "tool_response"):
    if _field in payload and not isinstance(payload[_field], dict):
        payload[_field] = {}

# Every field below is documented as a string but arrives as arbitrary JSON.
# A list `command` or a numeric `cwd` reaches a str-only call (.split(),
# .startswith(), os.path.*) and raises TypeError -> exit 1, which Codex
# reports as a hook error on an ordinary tool call. Drop any non-string value
# so the hook no-ops on it instead, per Part 6's "Fail open, always".
for _obj in (payload, payload.get("tool_input") or {}, payload.get("tool_response") or {}):
    for _key in ("command", "file_path", "cwd", "session_id", "transcript_path",
                 "content", "new_string", "old_string", "pattern", "path",
                 "agent_type", "last_assistant_message"):
        if _key in _obj and not isinstance(_obj[_key], str):
            _obj[_key] = ""

if payload.get("tool_name", "") != "Bash":
    sys.exit(0)

cmd = payload.get("tool_input", {}).get("command", "")
if not cmd:
    sys.exit(0)

HEREDOC_SHELLS = {"bash", "sh", "zsh", "dash", "ksh", "mksh", "ash"}


def strip_heredoc_bodies(text):
    # Heredoc bodies fed to a host shell stay scanned; everything else is data
    # that merely mentions a command name and must not false-positive. Fails
    # open to the original text on any parse error.
    try:
        out = []
        lines = text.split("\n")
        i = 0
        while i < len(lines):
            line = lines[i]
            out.append(line)
            delims = []
            for m in re.finditer(r"(?<!<)<<(?!<)-?\s*(['\"]?)(\w+)\1", line):
                head = {t.rsplit("/", 1)[-1].lstrip("\\") for t in line[: m.start()].split()}
                try:
                    head_tokens = shlex.split(line[:m.start()])
                except ValueError:
                    head_tokens = []
                remote_shell = False
                if head_tokens and os.path.basename(head_tokens[0].lstrip("\\")) in {"ssh", "mosh"}:
                    value_options = {"-B", "-b", "-c", "-D", "-E", "-e", "-F", "-I", "-i",
                                     "-J", "-L", "-l", "-m", "-O", "-o", "-p", "-Q", "-R",
                                     "-S", "-W", "-w"}
                    index = 1
                    while index < len(head_tokens):
                        token = head_tokens[index]
                        if token == "--":
                            index += 1
                            if index < len(head_tokens):
                                index += 1
                            break
                        if token in value_options:
                            index += 2
                            continue
                        if token.startswith("-"):
                            index += 1
                            continue
                        index += 1
                        break
                    remote_tokens = head_tokens[index:]
                    remote_shell = not remote_tokens or any(
                        os.path.basename(token) in HEREDOC_SHELLS for token in remote_tokens[:3]
                    )
                if remote_shell:
                    continue
                if not (head & HEREDOC_SHELLS):
                    delims.append(m.group(2))
            i += 1
            for delim in delims:
                while i < len(lines):
                    if lines[i].strip() == delim:
                        out.append(lines[i])
                        i += 1
                        break
                    i += 1
        return "\n".join(out)
    except Exception:
        return text


cmd = strip_heredoc_bodies(cmd)

if not re.search(r"\bgit\b|\bdd\b|\bshred\b|\bmkfs|\bwipefs\b", cmd):
    sys.exit(0)

GIT_GLOBAL_OPTS_WITH_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"}
WRAPPERS = {"command", "builtin", "env", "exec", "nohup", "setsid", "nice",
            "ionice", "stdbuf", "time", "timeout", "sudo", "doas"}


def mask_quotes(text):
    # Replace quoted content and escaped chars with spaces (same length) so a
    # separator regex only ever matches LIVE shell syntax — a `|` inside a
    # quoted grep pattern must never be treated as a pipe (D1).
    out = []
    quote = None
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if quote is not None:
            if quote == '"' and c == "\\" and i + 1 < n:
                out.append("  ")
                i += 2
                continue
            if c == quote:
                quote = None
                out.append(c)
            else:
                out.append("\n" if c == "\n" else " ")
            i += 1
            continue
        if c in ("'", '"'):
            quote = c
            out.append(c)
            i += 1
            continue
        if c == "\\" and i + 1 < n:
            out.append("  ")
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def split_subcmds(text):
    # Split on masked positions but slice the ORIGINAL text (same length,
    # so offsets line up) — separators inside quotes are never split on.
    masked = mask_quotes(text)
    last = 0
    for m in re.finditer(r"[\n;]|&&|\|\||[|&]", masked):
        yield text[last:m.start()]
        last = m.end()
    yield text[last:]


def strip_wrappers(tokens):
    # Strip wrapper/alias-bypass prefixes and env assignments (any case):
    # \dd, command dd, env [KEY=VAL...] dd, KEY=VAL dd, timeout 60 dd
    clean = [tok.lstrip("\\") for tok in tokens]
    while clean:
        head = clean[0]
        if head in WRAPPERS:
            clean.pop(0)
            while clean and (clean[0].startswith("-")
                             or re.fullmatch(r"[0-9]+(\.[0-9]+)?[smhd]?", clean[0])):
                clean.pop(0)
            continue
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", head):
            clean.pop(0)
            continue
        break
    return clean


def basename_of(tok):
    # /bin/dd, /usr/bin/git -> dd, git — a full path must not dodge detection.
    return tok.rsplit("/", 1)[-1]


def is_remote_or_guest(clean):
    if not clean:
        return False
    head = basename_of(clean[0])
    if head in {"ssh", "mosh", "systemd-nspawn"}:
        return True
    subcommand_options = {
        "docker": {"-H", "--host", "--context", "--config", "--log-level",
                   "--tlscacert", "--tlscert", "--tlskey"},
        "podman": {"--url", "--connection", "--runtime", "--root", "--runroot"},
        "incus": {"--project", "--config"},
        "lxc": {"--project", "--config"},
        "kubectl": {"--context", "--namespace", "-n", "--cluster", "--user"},
    }
    if head in {"docker-compose", "podman-compose"}:
        return len(clean) > 1 and clean[1] in {"exec", "run"}
    if head in subcommand_options:
        index = 1
        while index < len(clean):
            token = clean[index]
            if token in subcommand_options[head]:
                index += 2
                continue
            if token.startswith("--") and "=" in token:
                index += 1
                continue
            if token.startswith("-"):
                index += 1
                continue
            break
        if head in {"docker", "podman"} and index < len(clean) and clean[index] == "compose":
            index += 1
        if index < len(clean) and clean[index] == "container":
            index += 1
        return index < len(clean) and clean[index] in {"exec", "run", "shell", "debug"}
    guest_subcommands = {
        "incus": {"exec", "shell", "file"},
        "lxc": {"exec", "shell", "file"},
        "kubectl": {"exec", "debug"},
        "machinectl": {"shell"},
        "vagrant": {"ssh"},
        "multipass": {"exec", "shell"},
        "distrobox": {"enter"},
        "toolbox": {"run"},
    }
    return len(clean) > 1 and clean[1] in guest_subcommands.get(head, set())


def ssh_payload(clean):
    if not clean or basename_of(clean[0]) not in {"ssh", "mosh"}:
        return []
    value_options = {"-B", "-b", "-c", "-D", "-E", "-e", "-F", "-I", "-i",
                     "-J", "-L", "-l", "-m", "-O", "-o", "-p", "-Q", "-R",
                     "-S", "-W", "-w"}
    index = 1
    while index < len(clean):
        token = clean[index]
        if token == "--":
            index += 1
            if index < len(clean):
                index += 1
            break
        if token in value_options:
            index += 2
            continue
        if token.startswith("-"):
            index += 1
            continue
        index += 1
        break
    return clean[index:]


violations = []
seen_subshell_recursion = set()


def scan_tokens(clean, sub_cmd, depth=0):
    if depth > 5 or not clean:
        return
    head = basename_of(clean[0])

    # Apply destructive-operation checks to local host commands only.
    # Splitting still checks separate local commands in the same shell chain.
    if basename_of(clean[0]) in {"ssh", "mosh"}:
        remote = ssh_payload(clean)
        if remote:
            remote_command = " ".join(remote)
            for nested in split_subcmds(remote_command):
                nested = nested.strip()
                if not nested:
                    continue
                try:
                    nested_tokens = shlex.split(nested)
                except ValueError:
                    nested_tokens = nested.split()
                scan_tokens(strip_wrappers(nested_tokens), nested, depth + 1)
        return
    if is_remote_or_guest(clean):
        return

    if head == "dd":
        violations.append((sub_cmd, "dd"))
        return

    if head == "shred":
        violations.append((sub_cmd, "shred"))
        return

    if head == "wipefs":
        violations.append((sub_cmd, "wipefs"))
        return

    if head.startswith("mkfs"):
        violations.append((sub_cmd, "mkfs*"))
        return

    if head == "git":
        rest = clean[1:]
        i = 0
        while i < len(rest):
            tok = rest[i]
            if tok in GIT_GLOBAL_OPTS_WITH_VALUE:
                i += 2
                continue
            if tok.startswith("-"):
                i += 1
                continue
            if tok == "reset":
                violations.append((sub_cmd, "git reset"))
            break
        return

    # xargs -I{} dd ... / xargs dd ... — xargs invokes its trailing command
    # directly, so the real target is whatever follows xargs's own options.
    if head == "xargs":
        rest = clean[1:]
        i = 0
        while i < len(rest) and rest[i].startswith("-"):
            # -I{} and -n1 etc. take no separate value token in common usage;
            # -a file / -d delim / -P n / -L n / -s n take one.
            if re.fullmatch(r"-[adPLs]", rest[i]) and i + 1 < len(rest):
                i += 2
            else:
                i += 1
        if i < len(rest):
            scan_tokens(rest[i:], sub_cmd, depth + 1)
        return

    # bash -c '...' / sh -c "..." — recurse into the quoted payload so a
    # destructive command hidden behind an explicit sub-shell -c is caught.
    if head in ("bash", "sh", "zsh", "dash", "ksh", "mksh", "ash") and id(clean) not in seen_subshell_recursion:
        rest = clean[1:]
        for i, tok in enumerate(rest):
            if tok == "-c" and i + 1 < len(rest):
                seen_subshell_recursion.add(id(clean))
                for nested in split_subcmds(rest[i + 1]):
                    nested = nested.strip()
                    if not nested:
                        continue
                    try:
                        nested_tokens = shlex.split(nested)
                    except ValueError:
                        nested_tokens = nested.split()
                    scan_tokens(strip_wrappers(nested_tokens), nested, depth + 1)
                return


for sub_cmd in split_subcmds(cmd):
    sub_cmd = sub_cmd.strip()
    if not sub_cmd:
        continue

    # Peel a wrapping subshell/command-substitution: (dd if=x of=y),
    # $(dd if=x of=y), `dd if=x of=y` — the parens/backticks are shell
    # syntax, not part of the command name (D2).
    inner = sub_cmd
    m = re.match(r"^\$?\(([\s\S]*)\)$", inner) or re.match(r"^`([\s\S]*)`$", inner)
    if m:
        inner = m.group(1).strip()

    try:
        tokens = shlex.split(inner)
    except ValueError:
        tokens = inner.split()

    clean = strip_wrappers(tokens)
    if not clean:
        continue

    scan_tokens(clean, sub_cmd)

if not violations:
    sys.exit(0)

msg = (
    "BLOCKED: destructive operation denied on the local host or remote shell (git reset, dd, shred,\n"
    "mkfs*, wipefs).\n\n"
    "These are blocked locally and in parsed SSH/Mosh payloads, but a wrapper\n"
    "(\\cmd, command cmd, env KEY=VAL cmd) can slip past its raw glob\n"
    "match. This hook re-enforces the same policy after stripping wrappers.\n\n"
    "SSH payloads are checked for these operations; recognized guest payloads are exempt.\n"
    "Host commands in the same compound command remain checked.\n\n"
    "Violating command(s):\n"
)
for sub, verb in violations:
    msg += f"  {sub}  (denied: {verb})\n"

print(msg)
sys.stderr.write(msg + "\n")
sys.exit(2)
PYEOF

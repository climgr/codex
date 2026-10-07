#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202609170001-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  no-force-push.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Friday, May 01, 2026 10:22 EDT
# @@File             :  no-force-push.sh
# @@Description      :  PreToolUse hook: block git push --force/-f/+refspec (gitcommit is the only sanctioned push path)
# @@Changelog        :  20261007: Scan shell -c commands behind common wrappers.
# @@TODO             :  None
# @@Other            :  Blocks everywhere, including the zone — force-push has no zone exception.
# @@Resource         :  local_system_zone.md - "Still hard - no exception, ever"
# @@Terminal App     :  no
# @@sudo/root        :  no
# @@Template         :  shell/bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC1001,SC1003,SC2001,SC2003,SC2016,SC2031,SC2090,SC2115,SC2120,SC2155,SC2199,SC2229,SC2317,SC2329
# - - - - - - - - - - - - - - - - - - - - - - - - -
VERSION="202610070003-git"
# - - - - - - - - - - - - - - - - - - - - - - - - -
set -euo pipefail

# A broken hook must fail OPEN (exit 0) so it never silently blocks every Bash call.
if ! command -v python3 >/dev/null 2>&1; then
  printf 'no-force-push.sh: required command not found: python3 (hook disabled, failing open)\n' >&2
  exit 0
fi

NO_FORCE_PUSH_INPUT="$(cat)"

NO_FORCE_PUSH_INPUT_TMPFILE="$(mktemp)"
trap 'rm -f "$NO_FORCE_PUSH_INPUT_TMPFILE"' EXIT
printf '%s' "$NO_FORCE_PUSH_INPUT" > "$NO_FORCE_PUSH_INPUT_TMPFILE"

python3 - "$NO_FORCE_PUSH_INPUT_TMPFILE" <<'PYEOF'
import json
import os
import re
import shlex
import sys


def split_shell_commands(text):
    # Split shell control operators only outside quotes and comments. Search
    # patterns and other quoted data may contain these characters verbatim.
    operators = ("&&", "||", "\n", ";", "|", "&")
    parts = []
    start = 0
    quote = None
    escaped = False
    comment = False
    i = 0
    while i < len(text):
        char = text[i]
        if comment:
            if char == "\n":
                parts.append(text[start:i])
                start = i + 1
                comment = False
            i += 1
            continue
        if escaped:
            escaped = False
            i += 1
            continue
        if quote == "'":
            if char == "'":
                quote = None
            i += 1
            continue
        if quote == '"':
            if char == "\\":
                escaped = True
            elif char == '"':
                quote = None
            i += 1
            continue
        if char == "\\":
            escaped = True
            i += 1
            continue
        if char in ("'", '"'):
            quote = char
            i += 1
            continue
        if char == "#" and (
            i == 0 or text[i - 1].isspace() or text[i - 1] in ";&|"
        ):
            comment = True
            i += 1
            continue
        operator = next((op for op in operators if text.startswith(op, i)), None)
        if operator:
            parts.append(text[start:i])
            i += len(operator)
            start = i
            continue
        i += 1
    parts.append(text[start:])
    return expand_shell_commands(parts)


def expand_shell_commands(parts):
    shells = {"bash", "sh", "zsh", "dash", "ksh", "mksh", "ash", "fish"}
    expanded = []
    pending = list(parts)
    while pending:
        part = pending.pop(0)
        try:
            tokens = shlex.split(part, comments=True)
        except ValueError:
            expanded.append(part)
            continue
        index = 0
        while index < len(tokens):
            name = os.path.basename(tokens[index].lstrip("\\"))
            if name in shells:
                break
            if name in ("command", "builtin", "exec", "nohup", "time"):
                if name == "command" and index + 1 < len(tokens) \
                        and tokens[index + 1] in ("-v", "-V"):
                    index = len(tokens)
                    break
                index += 1
                if index < len(tokens) and tokens[index] == "--":
                    index += 1
                continue
            if name == "env":
                index += 1
                while index < len(tokens):
                    token = tokens[index]
                    if token == "--":
                        index += 1
                        break
                    if token in ("-u", "--unset", "-C", "--chdir"):
                        index += 2
                    elif token.startswith("-") or re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", token):
                        index += 1
                    else:
                        break
                continue
            if name in ("sudo", "doas"):
                index += 1
                value_options = {"-u", "--user", "-g", "--group", "-h", "--host",
                                 "-p", "--prompt", "-C", "--close-from", "-r", "--role",
                                 "-t", "--type"}
                while index < len(tokens):
                    token = tokens[index]
                    if token in value_options:
                        index += 2
                    elif token.startswith("--") and "=" in token:
                        index += 1
                    elif token.startswith("-") or re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", token):
                        index += 1
                    else:
                        break
                continue
            if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tokens[index]):
                index += 1
                continue
            index = len(tokens)
            break
        if index >= len(tokens) or os.path.basename(tokens[index].lstrip("\\")) not in shells:
            expanded.append(part)
            continue
        script = None
        for option_index, token in enumerate(tokens[index + 1:], index + 1):
            if token in ("-c", "--command") and option_index + 1 < len(tokens):
                script = tokens[option_index + 1]
                break
            if token.startswith("--command="):
                script = token.split("=", 1)[1]
                break
            if token.startswith("-") and not token.startswith("--") and "c" in token[1:] \
                    and option_index + 1 < len(tokens):
                script = tokens[option_index + 1]
                break
        if script is None:
            expanded.append(part)
        else:
            pending[0:0] = split_shell_commands(script)
    return expanded


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
HEREDOC_CONTAINER_TOOLS = {"docker", "docker-compose", "podman", "podman-compose",
                           "kubectl", "incus", "lxc", "machinectl", "systemd-nspawn",
                           "vagrant", "multipass", "distrobox", "toolbox", "virsh",
                           "nsenter", "chroot"}


def strip_heredoc_bodies(text):
    # Non-shell heredoc bodies are data, not commands - drop them before scanning
    # so a cat/tee/python3 heredoc that merely MENTIONS a blocked command is not a
    # false positive. Bodies fed to a host shell (bash <<EOF) stay fully scanned;
    # container/VM-mediated shells (docker exec -i c bash <<EOF) are exempt - the
    # body runs inside the disposable guest. Fails open to the original text on
    # any parse error so scanning never silently weakens.
    try:
        out = []
        lines = text.split("\n")
        i = 0
        while i < len(lines):
            line = lines[i]
            out.append(line)
            delims = []
            # A pipe, command substitution, or backtick on the line can route
            # a "data" heredoc body into a shell downstream of a non-shell
            # head (e.g. `cat <<EOF | bash`) - never elide on such lines.
            risky_line = bool(re.search(r"\||\$\(|`", line))
            for m in re.finditer(r"(?<!<)<<(?!<)-?\s*(['\"]?)(\w+)\1", line):
                if risky_line:
                    continue
                head = {t.rsplit("/", 1)[-1].lstrip("\\") for t in line[: m.start()].split()}
                if head & HEREDOC_CONTAINER_TOOLS or not (head & HEREDOC_SHELLS):
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

# Cheap pre-filter: nothing resembling git push anywhere -> allow.
if not re.search(r"\bgit\b", cmd):
    sys.exit(0)


def is_force_push(tokens):
    # tokens = argv of one sub-command, wrapper/env prefixes already stripped
    if not tokens or tokens[0] != "git":
        return False
    # git [global-opts] push ... -- find the subcommand
    try:
        push_idx = tokens.index("push")
    except ValueError:
        return False
    for tok in tokens[push_idx + 1:]:
        # Long forms: --force, --force=..., --force-with-lease*. Excludes
        # --force-if-includes: a safety constraint that only takes effect
        # combined with --force/--force-with-lease (already caught above),
        # not a force operation on its own — local_system_zone.md's "Still
        # hard" list names only `--force*`/`--force-with-lease` literally,
        # not this flag.
        if tok == "--force-if-includes":
            continue
        if tok == "--force" or tok.startswith("--force"):
            return True
        # Combined short flags: -f, -fu, -uf, etc. (not --long, not a refspec)
        if re.match(r"^-[a-zA-Z]*f[a-zA-Z]*$", tok):
            return True
        # +refspec force syntax: git push origin +main
        if tok.startswith("+") and len(tok) > 1:
            return True
    return False


# Examine each sub-command independently; newlines are separators too,
# so multi-line commands cannot hide a force-push on line 2+.
for sub in split_shell_commands(cmd):
    sub = sub.strip()
    if not sub:
        continue
    try:
        tokens = shlex.split(sub, comments=True)
    except ValueError:
        tokens = sub.split()

    # Strip wrapper/alias-bypass prefixes and env assignments (any case):
    # \git, command git, env [KEY=VAL...] git, KEY=VAL git
    clean = []
    skipping_prefix = True
    for tok in tokens:
        if skipping_prefix:
            if tok in ("command", "env", "exec", "nohup", "time", "sudo", "doas"):
                continue
            if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tok):
                continue
            # env/command flags like -i or -p pass through the prefix stripper
            if tok.startswith("-"):
                continue
            skipping_prefix = False
        # shlex already removed a literal backslash from \git; handle raw fallback too
        clean.append(tok.lstrip("\\"))

    if is_force_push(clean):
        msg = (
            "BLOCKED: force-pushing is forbidden (git push --force / -f / --force-with-lease / +refspec).\n"
            "Force-pushing rewrites remote history, bypasses the signed-commit workflow, and\n"
            "can destroy collaborators' history.\n\n"
            "The only sanctioned commit+push path is:\n"
            "  gitcommit --dir {project_dir} all\n\n"
            "If a force-push is genuinely required (e.g. to fix a bad merge on a personal\n"
            "branch), ask the user to run it manually."
        )
        print(msg)
        sys.stderr.write(msg + "\n")
        sys.exit(2)

sys.exit(0)
PYEOF

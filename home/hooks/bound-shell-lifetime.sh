#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202609170001-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  bound-shell-lifetime.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Friday, Jul 03, 2026 12:30 EDT
# @@File             :  bound-shell-lifetime.sh
# @@Description      :  Codex PreToolUse hook — block unbounded shell lifetimes (infinite poll loops, open-ended sleeps/follows, untracked daemonization)
# @@Changelog        :  Decode the stdin payload file as UTF-8 with replacement and fail open on any parse exception (not only JSONDecodeError) — a non-UTF-8 byte previously raised UnicodeDecodeError and surfaced as a hook error. Never elide a heredoc body on a line with a pipe, $( or backtick (cat <<EOF | bash routes the body into a host shell), matching the other heredoc-aware hooks.
# @@TODO             :  None
# @@Other            :  `timeout N`-wrapped and container-mediated commands are exempt; bounded loops (counters, seq, {1..N}, SECONDS) are allowed.
# @@Resource         :  ~/.codex/memory/execution_hierarchy.md
# @@Terminal App     :  no
# @@sudo/root        :  no
# @@Template         :  shell/bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC1001,SC1003,SC2001,SC2003,SC2016,SC2031,SC2090,SC2115,SC2120,SC2155,SC2199,SC2229,SC2317,SC2329
# - - - - - - - - - - - - - - - - - - - - - - - - -
VERSION="202609170001-git"
# - - - - - - - - - - - - - - - - - - - - - - - - -
set -euo pipefail

# __require_cmd <name> - bail with a clear error if a required tool is missing.
# A broken hook exits 0 (no-op) so we never silently block every Bash call.
__require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'bound-shell-lifetime.sh: required command not found: %s\n' "$1" >&2
    exit 0
  fi
}

__require_cmd python3

BOUND_SHELL_LIFETIME_INPUT="$(cat)"

BOUND_SHELL_LIFETIME_INPUT_TMPFILE="$(mktemp)"
trap 'rm -f "$BOUND_SHELL_LIFETIME_INPUT_TMPFILE"' EXIT
printf '%s' "$BOUND_SHELL_LIFETIME_INPUT" > "$BOUND_SHELL_LIFETIME_INPUT_TMPFILE"

python3 - "$BOUND_SHELL_LIFETIME_INPUT_TMPFILE" <<'PYEOF'
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

SHELLS = ("sh", "bash", "zsh", "dash", "ksh", "mksh")
CONTAINER_TOOLS = ("docker", "docker-compose", "podman", "kubectl", "incus", "lxc")
# maximum single sleep in seconds before we call it open-ended
MAX_SLEEP = 600

HEREDOC_SHELLS = {"bash", "sh", "zsh", "dash", "ksh", "mksh", "ash"}
HEREDOC_CONTAINER_TOOLS = {"docker", "docker-compose", "podman", "podman-compose",
                           "kubectl", "incus", "lxc", "machinectl", "systemd-nspawn",
                           "vagrant", "multipass", "distrobox", "toolbox", "virsh",
                           "nsenter", "chroot"}


def strip_heredoc_bodies(text):
    # Non-shell heredoc bodies are data, not commands - drop them before scanning
    # so a cat/tee/python3 heredoc that merely MENTIONS "while true; do sleep" is
    # not a false positive. Bodies fed to a host shell (bash <<EOF) stay fully
    # scanned; container/VM-mediated shells (docker exec -i c bash <<EOF) are
    # exempt - the body runs inside the disposable guest. Fails open to the
    # original text on any parse error so scanning never silently weakens.
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


def mask_quotes(text):
    # replace quoted content and escaped chars with spaces so patterns only match live shell syntax
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


def sub_scripts(text):
    # returns script and outer_bounded pairs for -c payloads of shell interpreters,
    # so quoted loops cannot hide. Container-mediated invocations are skipped entirely
    # (the guest owns that lifetime, not the host). A timeout prefix does NOT skip
    # recursion here — sentinel polling is forbidden unconditionally, even when
    # timeout- or iteration-capped, per shell_lifetime_conventions.md — it only marks
    # outer_bounded so an ordinary (non-sentinel) loop inside is recognized as bounded.
    try:
        tokens = shlex.split(text)
    except ValueError:
        return []
    found = []
    for i, tok in enumerate(tokens):
        base = tok.rsplit("/", 1)[-1]
        if base not in SHELLS:
            continue
        prior = [t.rsplit("/", 1)[-1] for t in tokens[:i]]
        if any(t in CONTAINER_TOOLS for t in prior):
            continue
        outer_bounded = "timeout" in prior
        j = i + 1
        script = None
        while j < len(tokens):
            if tokens[j] == "-c":
                if j + 1 < len(tokens):
                    script = tokens[j + 1]
                break
            if not tokens[j].startswith("-"):
                break
            j += 1
        if script:
            found.append((script, outer_bounded))
    return found


def sleep_seconds(arg):
    # parse a sleep argument into seconds; None if not parseable
    if arg in ("infinity", "inf"):
        return float("inf")
    m = re.fullmatch(r"([0-9]*\.?[0-9]+)([smhd]?)", arg)
    if not m:
        return None
    mult = {"": 1, "s": 1, "m": 60, "h": 3600, "d": 86400}[m.group(2)]
    return float(m.group(1)) * mult


def bounded_before(masked, pos):
    # a `timeout N` earlier in the command bounds everything after it
    return re.search(r"\btimeout\s+[0-9]", masked[:pos]) is not None


violations = []


def check(text, depth=0, outer_bounded=False):
    masked = mask_quotes(re.sub(r"\\\n\s*", " ", text))

    # rule A: unbounded while/until loop that sleeps — the classic forever-poll
    for m in re.finditer(r"\b(while|until)\b(.{0,400}?)\bdo\b(.{0,2000}?)\bdone\b", masked, re.S):
        cond, body = m.group(2), m.group(3)
        if not re.search(r"\bsleep\b", body):
            continue
        if re.search(r"-lt\b|-le\b|-ge\b|-gt\b|\bseq\b|\{1\.\.|\bSECONDS\b|\(\(", cond + body):
            continue
        if outer_bounded or bounded_before(masked, m.start()):
            continue
        # Sentinel-file polling (shell_lifetime_conventions.md's example is
        # exactly *.done) is a harness-tracked-work poll, not a general
        # external-state poll — still subject to the Exemptions section's
        # blanket `timeout {n}`/iteration-cap carve-out above, same as any
        # other loop, so this check runs after it, not before.
        if re.search(r"\.done\b", cond):
            snippet = re.sub(r"\s+", " ", text[m.start():m.end()])[:120]
            violations.append(("sentinel-poll", snippet,
                "Never poll for subagent/background-task completion — the harness sends a task-notification when tracked work finishes. Drop the loop entirely."))
            continue
        snippet = re.sub(r"\s+", " ", text[m.start():m.end()])[:120]
        violations.append(("unbounded-loop", snippet,
            "Wrap in `timeout <seconds>` sized to the operation, or add an iteration cap (e.g. `i=0; until <cond> || [ $i -ge 60 ]; do i=$((i+1)); sleep 5; done`)."))

    # rule A2: for ((;;)) infinite loop with sleep
    for m in re.finditer(r"\bfor\s*\(\(\s*;;\s*\)\)(.{0,2000}?)\bdone\b", masked, re.S):
        if re.search(r"\bsleep\b", m.group(1)) and not (outer_bounded or bounded_before(masked, m.start())):
            snippet = re.sub(r"\s+", " ", text[m.start():m.end()])[:120]
            violations.append(("unbounded-loop", snippet,
                "Wrap in `timeout <seconds>` or add an iteration cap."))

    # rule B: open-ended or oversized single sleep
    for m in re.finditer(r"(?:^|[;&|()\n]\s*)sleep\s+(\S+)", masked):
        if bounded_before(masked, m.start()):
            continue
        secs = sleep_seconds(m.group(1))
        if secs is not None and secs > MAX_SLEEP:
            violations.append(("long-sleep", "sleep " + m.group(1),
                "Max single sleep is 600s. For longer waits end the turn and let notifications/schedulers resume the work."))

    # rule C: detachment escapes both the tool timeout and task tracking
    for m in re.finditer(r"(?:^|[;&|()\n]\s*)(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*(nohup|setsid)\b", masked):
        violations.append((m.group(1), m.group(1),
            "Detached processes are untracked and unkillable by task tooling. Use run_in_background (tracked, notifies on exit, stoppable) instead."))
    if re.search(r"(?:^|[;&|()\n]\s*)disown\b", masked):
        violations.append(("disown", "disown",
            "Disowned jobs outlive the session untracked. Use run_in_background instead."))

    # rule D: follow-mode readers and watch never end on their own
    for m in re.finditer(r"(?:^|[;&|()\n]\s*)(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*tail\s+([^;&|\n]*)", masked):
        if re.search(r"(?:^|\s)-[A-Za-z]*[fF]\b|--follow", m.group(1)) and not bounded_before(masked, m.start()):
            violations.append(("tail-follow", "tail " + m.group(1).strip()[:80],
                "Wrap in `timeout <seconds>`, or read the file directly (tail -n N) — follow mode never exits."))
    for m in re.finditer(r"(?:^|[;&|()\n]\s*)watch\s", masked):
        if not bounded_before(masked, m.start()):
            violations.append(("watch", "watch ...",
                "Wrap in `timeout <seconds>` or run the command once — watch never exits."))

    # rule E: & backgrounding without PID capture or a closing wait leaks a process
    for m in re.finditer(r"&", masked):
        i = m.start()
        prev_c = masked[i - 1:i]
        next_c = masked[i + 1:i + 2]
        if next_c in ("&", ">") or prev_c in ("&", "|", ">", "<"):
            continue
        if "$!" in text or re.search(r"\bwait\b", masked):
            continue
        violations.append(("untracked-background", re.sub(r"\s+", " ", text[max(0, i - 40):i + 1])[-60:],
            "Capture the PID at launch (`cmd & PID=$!`) or close with `wait`; prefer run_in_background so the task is tracked and stoppable."))
        break

    # recurse into sh -c payloads so quoted loops cannot hide (depth-limited)
    if depth < 2:
        for script, script_bounded in sub_scripts(text):
            check(script, depth + 1, outer_bounded=script_bounded)


check(cmd)

if not violations:
    sys.exit(0)

msg = "BLOCKED: unbounded shell lifetime detected.\n\n"
for rule, snippet, fix in violations:
    msg += "  [" + rule + "] " + snippet + "\n    Fix: " + fix + "\n"
msg += (
    "\nTimeout tiers — every command must be bounded to its operation:\n"
    "  lookups/status <=60s | network/package ops <=300s | builds/tests <=600s\n"
    "Commands already wrapped in `timeout N` and container-mediated payloads are exempt.\n"
    "Waiting on harness-tracked work (subagents, background tasks) needs NO polling —\n"
    "a task-notification arrives when it finishes."
)

print(msg)
sys.stderr.write(msg + "\n")
sys.exit(2)
PYEOF

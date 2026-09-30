#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202609170001-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  enforce-commit-mess-coverage.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Wednesday, Sep 03, 2026 15:45 EDT
# @@File             :  enforce-commit-mess-coverage.sh
# @@Description      :  PreToolUse Bash hook: blocks `gitcommit --dir <path> all` when the working tree has changed/untracked files that COMMIT_MESS's `- path:` bullets do not cover.
# @@Changelog        :  Decode the stdin payload file as UTF-8 with replacement and fail open on any parse exception (not only JSONDecodeError) — a non-UTF-8 byte previously raised UnicodeDecodeError and surfaced as a hook error.
# @@TODO             :  None
# @@Other            :  Coverage is one-directional by design: every changed file needs a bullet; extra prose bullets are fine. A bullet ending in `/` covers the whole directory; `*` bullets glob-match.
# @@Resource         :  AGENTS.md - Commit Workflow · home/memory/gitcommit_conventions.md
# @@Terminal App     :  no
# @@sudo/root        :  no
# @@Template         :  shell/bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC1001,SC1003,SC2001,SC2003,SC2016,SC2031,SC2090,SC2115,SC2120,SC2155,SC2199,SC2229,SC2317,SC2329
# - - - - - - - - - - - - - - - - - - - - - - - - -
VERSION="202609170001-git"
# - - - - - - - - - - - - - - - - - - - - - - - - -
set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  printf 'enforce-commit-mess-coverage.sh: required command not found: python3 (hook disabled, failing open)\n' >&2
  exit 0
fi

ENFORCE_COVERAGE_INPUT="$(cat)"

ENFORCE_COVERAGE_INPUT_TMPFILE="$(mktemp)"
trap 'rm -f "$ENFORCE_COVERAGE_INPUT_TMPFILE"' EXIT
printf '%s' "$ENFORCE_COVERAGE_INPUT" > "$ENFORCE_COVERAGE_INPUT_TMPFILE"

python3 - "$ENFORCE_COVERAGE_INPUT_TMPFILE" <<'PYEOF'
import fnmatch
import json
import os
import re
import shlex
import subprocess
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

# Normalise a non-object tool_input so every downstream .get() chain
# below stays safe without each call site needing its own type check.
if "tool_input" in payload and not isinstance(payload["tool_input"], dict):
    payload["tool_input"] = {}

# Documented-string fields can arrive as arbitrary JSON; drop non-string
# values so the hook no-ops on them, per Part 6's "Fail open, always".
for _obj in (payload, payload.get("tool_input") or {}):
    for _key in ("command", "cwd", "session_id", "transcript_path"):
        if _key in _obj and not isinstance(_obj[_key], str):
            _obj[_key] = ""

if payload.get("tool_name", "") != "Bash":
    sys.exit(0)

cmd = payload.get("tool_input", {}).get("command", "")
if not cmd or not re.search(r"\bgitcommit\b", cmd):
    sys.exit(0)

HEREDOC_SHELLS = {"bash", "sh", "zsh", "dash", "ksh", "mksh", "ash"}
HEREDOC_CONTAINER_TOOLS = {"docker", "docker-compose", "podman", "podman-compose",
                           "kubectl", "incus", "lxc", "machinectl", "systemd-nspawn",
                           "vagrant", "multipass", "distrobox", "toolbox", "virsh",
                           "nsenter", "chroot"}


def strip_heredoc_bodies(text):
    # Non-shell heredoc bodies are data, not commands — drop them before scanning
    # so a cat/tee/python3 heredoc that merely MENTIONS gitcommit is not a false
    # positive. Bodies fed to a host shell (bash <<EOF) stay fully scanned;
    # container/VM-mediated shells are exempt. Fails open to the original text
    # on any parse error so scanning never silently weakens.
    try:
        out = []
        lines = text.split("\n")
        i = 0
        while i < len(lines):
            line = lines[i]
            out.append(line)
            delims = []
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

# Collect every `gitcommit --dir <abs-path> all` target in the command.
# Shape violations themselves are enforce-gitcommit-shape.sh's job — this
# hook only checks message coverage for well-formed invocations.
target_dirs = []
for sub_cmd in re.split(r"[\n;]|&&|\|\||[|&]", cmd):
    sub_cmd = sub_cmd.strip()
    if not sub_cmd:
        continue
    try:
        tokens = shlex.split(sub_cmd)
    except ValueError:
        tokens = sub_cmd.split()
    clean = []
    skipping_prefix = True
    for tok in tokens:
        if skipping_prefix:
            if tok in ("command", "env", "exec", "nohup", "time", "sudo", "doas"):
                continue
            if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tok):
                continue
            if tok.startswith("-"):
                continue
            skipping_prefix = False
        clean.append(tok.lstrip("\\"))
    if len(clean) == 4 and clean[0] == "gitcommit" and clean[1] == "--dir" \
            and clean[3] == "all" and clean[2].startswith("/"):
        target_dirs.append(clean[2])

if not target_dirs:
    sys.exit(0)


def changed_files(repo):
    # Returns the paths `gitcommit all` will sweep up, from porcelain -z
    # (rename-safe, newline-safe). None on any git failure -> fail open.
    try:
        proc = subprocess.run(
            ["git", "-C", repo, "status", "--porcelain", "-z"],
            capture_output=True, timeout=8,
        )
    except Exception:
        return None
    if proc.returncode != 0:
        return None
    entries = proc.stdout.decode("utf-8", "replace").split("\0")
    paths = []
    i = 0
    while i < len(entries):
        entry = entries[i]
        i += 1
        if len(entry) < 4:
            continue
        status, path = entry[:2], entry[3:]
        paths.append(path)
        # Renames/copies carry the origin path as the NEXT NUL field; it is
        # part of this entry, not an independent change — skip it.
        if status[0] in ("R", "C"):
            i += 1
    return paths


def documented_paths(mess_text):
    # `- path: change` bullets; backticks around the path are tolerated.
    docs = set()
    for line in mess_text.split("\n"):
        m = re.match(r"^\s*-\s+`?([^`:\s]+)`?\s*:", line)
        if m:
            docs.add(m.group(1).lstrip("./"))
    return docs


def is_covered(path, docs):
    p = path.lstrip("./")
    for d in docs:
        if p == d or p.rstrip("/") == d.rstrip("/"):
            return True
        # A directory bullet (trailing slash, or porcelain's untracked-dir
        # form on the other side) covers everything beneath it.
        if p.startswith(d.rstrip("/") + "/") or d.startswith(p.rstrip("/") + "/"):
            return True
        if ("*" in d or "?" in d) and fnmatch.fnmatch(p, d):
            return True
    return False


problems = []
for repo in target_dirs:
    if not os.path.isdir(os.path.join(repo, ".git")):
        continue
    files = changed_files(repo)
    if files is None:
        continue
    if not files:
        continue
    mess_path = os.path.join(repo, ".git", "COMMIT_MESS")
    try:
        with open(mess_path, "r", encoding="utf-8", errors="replace") as f:
            mess = f.read()
    except OSError:
        mess = ""
    if not mess.strip():
        problems.append((repo, files, "COMMIT_MESS is missing or empty"))
        continue
    docs = documented_paths(mess)
    uncovered = [p for p in files if not is_covered(p, docs)]
    if uncovered:
        problems.append((repo, uncovered, None))

if not problems:
    sys.exit(0)

msg = "BLOCKED: gitcommit would sweep files COMMIT_MESS does not describe.\n\n"
for repo, files, reason in problems:
    if reason:
        msg += f"{repo}: {reason} — write {repo}/.git/COMMIT_MESS from the actual diff first.\n"
        continue
    msg += (
        f"{repo}: {len(files)} changed/untracked file(s) have no `- path: change` "
        "bullet in .git/COMMIT_MESS:\n"
    )
    for p in files[:20]:
        msg += f"  {p}\n"
    if len(files) > 20:
        msg += f"  ... and {len(files) - 20} more\n"
msg += (
    "\n`gitcommit --dir <path> all` commits EVERY dirty file in the tree, not "
    "just the ones in recent context. Re-run `git status --porcelain` + "
    "`git diff --stat`, then either rewrite COMMIT_MESS to describe every file "
    "(gitcommit_conventions.md: every changed file described, never from "
    "memory) or, if unrelated work has accumulated, split per the grouping "
    "rules before committing. A directory bullet (`- dir/: ...`) covers files "
    "beneath it.\n"
)
print(msg)
sys.stderr.write(msg + "\n")
sys.exit(2)
PYEOF

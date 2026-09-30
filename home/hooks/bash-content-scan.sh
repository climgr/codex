#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202609170001-git
# @@Author           :  Jason Hempstead
# @@Contact          :  git-admin@casjaysdev.pro
# @@License          :  WTFPL
# @@ReadME           :  bash-content-scan.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Sunday, August 30, 2026 18:00 EDT
# @@File             :  bash-content-scan.sh
# @@Description      :  PreToolUse Bash hook: scans no-secrets.sh/no-ai-attribution.sh patterns against heredoc or echo/printf redirects, which bypass Write/Edit tool_input.
# @@Changelog        :  Decode the stdin payload file as UTF-8 with replacement and fail open on any parse exception (not only JSONDecodeError) — a non-UTF-8 byte previously raised UnicodeDecodeError and surfaced as a hook error.
# @@TODO             :  None
# @@Other            :  Secrets respect the zone's plaintext-credential exemption (cwd-scoped); AI-attribution has no exemption; container/VM-mediated heredocs are exempt.
# @@Resource         :  home/hooks/no-secrets.sh, home/hooks/no-ai-attribution.sh
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
  printf 'bash-content-scan.sh: required command not found: python3 (hook disabled, failing open)\n' >&2
  exit 0
fi

BASH_CONTENT_SCAN_INPUT="$(cat)"

BASH_CONTENT_SCAN_INPUT_TMPFILE="$(mktemp)"
trap 'rm -f "$BASH_CONTENT_SCAN_INPUT_TMPFILE"' EXIT
printf '%s' "$BASH_CONTENT_SCAN_INPUT" > "$BASH_CONTENT_SCAN_INPUT_TMPFILE"

python3 - "$BASH_CONTENT_SCAN_INPUT_TMPFILE" <<'PYEOF'
import json
import os
import re
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

CONTAINER_PREFIXES = {"docker", "docker-compose", "podman", "podman-compose",
                      "kubectl", "incus", "lxc", "machinectl", "systemd-nspawn",
                      "vagrant", "multipass", "distrobox", "toolbox", "virsh",
                      "nsenter", "chroot"}


def extract_heredoc_bodies(text):
    # Returns a list of (body_text, is_container_mediated, target_path) - the
    # body content written on disk-facing heredocs, so it can be scanned like
    # Write/Edit content. Container/VM-mediated heredocs are flagged so the
    # caller can skip them (the body runs inside a disposable guest, not the
    # host). target_path is the redirect target on the same line as the
    # heredoc marker, if any (e.g. `cat <<EOF > file.env.example`), so
    # callers can apply the same template-filename exemption Write/Edit use.
    bodies = []
    lines = text.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i]
        for m in re.finditer(r"(?<!<)<<(?!<)-?\s*(['\"]?)(\w+)\1", line):
            delim = m.group(2)
            head = {t.rsplit("/", 1)[-1].lstrip("\\") for t in line[: m.start()].split()}
            is_container = bool(head & CONTAINER_PREFIXES)
            target_m = re.search(r">>?\s*([^\s&|;<>]+)", line[m.end():])
            target = target_m.group(1) if target_m else ""
            body_lines = []
            j = i + 1
            while j < len(lines):
                if lines[j].strip() == delim:
                    break
                body_lines.append(lines[j])
                j += 1
            bodies.append(("\n".join(body_lines), is_container, target))
        i += 1
    return bodies


def extract_redirected_echo_printf(text):
    # echo/printf content redirected to a real file (> or >>), the other
    # common way a Bash command writes content without going through
    # Write/Edit. Best-effort - only literal-quoted or bare arguments before
    # the first > / >> on the same logical line. Returns (body, target_path).
    out = []
    for sub_cmd in re.split(r"[\n;]|&&|\|\|", text):
        sub_cmd = sub_cmd.strip()
        if not re.match(r"^(echo|printf)\b", sub_cmd):
            continue
        target_m = re.search(r">>?\s*([^&|\s]+)", sub_cmd)
        if not target_m:
            continue
        body = sub_cmd[: target_m.start()]
        out.append((body, target_m.group(1)))
    return out


# Exempted template/example env files - mirrors no-secrets.sh's ALLOWED_TEMPLATES
# so a heredoc/redirect writing a template file isn't flagged when the same
# content written via Write/Edit tool_input would be exempt.
ALLOWED_TEMPLATES = {
    ".env.example",
    ".env.sample",
    "app.env.example",
    "app.env.sample",
    "default.env.example",
    "default.env.sample",
}

segments = []
secret_segments = []
for body, is_container, target in extract_heredoc_bodies(cmd):
    if is_container:
        continue
    segments.append(body)
    if os.path.basename(target) not in ALLOWED_TEMPLATES:
        secret_segments.append(body)
for body, target in extract_redirected_echo_printf(cmd):
    segments.append(body)
    if os.path.basename(target) not in ALLOWED_TEMPLATES:
        secret_segments.append(body)

content = "\n".join(s for s in segments if s)
secret_content = "\n".join(s for s in secret_segments if s)
if not content:
    sys.exit(0)

# - - - secrets (mirrors no-secrets.sh) - - -
SECRET_PATTERNS = [
    ("AWS Access Key ID",        r"AKIA[0-9A-Z]{16}"),
    ("GitHub Token",             r"gh[pso]_[A-Za-z0-9]{36,}"),
    ("GitHub PAT (new format)",  r"github_pat_[A-Za-z0-9_]{82,}"),
    ("Slack Token",              r"xox[baprs]-[0-9A-Za-z\-]{10,}"),
    ("Stripe Live Secret Key",   r"sk_live_[A-Za-z0-9]{24,}"),
    ("Google API Key",           r"AIza[0-9A-Za-z\-_]{35}"),
    ("SendGrid API Key",         r"SG\.[A-Za-z0-9._\-]{22}\.[A-Za-z0-9._\-]{43}"),
    ("PEM Private Key",          r"-----BEGIN (?:RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----"),
    ("Anthropic API Key",        r"sk-ant-[A-Za-z0-9\-_]{40,}"),
    ("OpenAI API Key",           r"sk-proj-[A-Za-z0-9]{40,}"),
    ("npm Access Token",         r"npm_[A-Za-z0-9]{36,}"),
    ("JWT (3-part)",             r"eyJ[A-Za-z0-9_\-]{10,}\.eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}"),
    ("HuggingFace Token",        r"hf_[A-Za-z0-9]{34,}"),
    ("GitLab Token",             r"glpat-[A-Za-z0-9\-_]{20,}"),
    ("PyPI API Token",           r"pypi-[A-Za-z0-9_\-]{40,}"),
]
PLACEHOLDER_RE = re.compile(
    r"changeme"
    r"|placeholder"
    r"|your[_-]?(?:api[_-]?)?(?:key|token|secret|password)[_-]?here"
    r"|example"
    r"|dummy"
    r"|fake"
    r"|test[_-]?(?:key|token|secret)"
    r"|xxx+"
    r"|<[A-Za-z_][^>]*>"
    r"|\{[A-Za-z_][^}]*\}"
    r"|TO_BE"
    r"|FILL_IN"
    r"|REPLACE_ME"
    r"|INSERT_HERE"
    r"|YOUR_",
    re.IGNORECASE,
)


def redact(value):
    if len(value) <= 6:
        return "*" * len(value)
    return value[:4] + "*" * (len(value) - 6) + value[-2:]


# Local System Management Zone (~/Projects/local/system/**, see AGENTS.md) allows
# plaintext credentials. This cwd-path check is necessary but not sufficient:
# sensitive_data.md's "The Only Exceptions" conditions the zone exemption on
# confirmed PRIVATE repo visibility, which a hook cannot verify (AI.md's hook
# rules forbid network I/O, and a visibility check is network I/O). The Repo
# privacy gate — run at repo-creation and after every push, per AGENTS.md's
# zone section — is what actually keeps this exemption safe; this hook only
# narrows scope by path.
cwd = payload.get("cwd", "") or ""
zone_root = os.path.join(os.environ.get("HOME", "/root"), "Projects", "local", "system")
in_zone = cwd == zone_root or cwd.startswith(zone_root + os.sep)

findings = []
if not in_zone:
    for label, pattern in SECRET_PATTERNS:
        for m in re.finditer(pattern, secret_content):
            if PLACEHOLDER_RE.search(m.group(0)):
                continue
            findings.append(f"secret: {label}: {redact(m.group())}")

# - - - AI attribution (mirrors no-ai-attribution.sh) - - -
_verbs = r"(generated|written|created|authored|built|made|assisted)"
_conn = r"(by|with|using)"
_ai = r"(codex|openai|claude|anthropic|an? ai\b)"
_hyph = r"(-|‑)"
_ca = r"co" + _hyph + r"authored" + _hyph + r"by"
_gen = r"generated"
ATTRIBUTION_PATTERN = re.compile(
    _verbs + r"\s+" + _conn + r"\s+" + _ai
    + r"|" + _ca + r":\s*(codex|openai|claude|anthropic)"
    + r"|co_authored_by:\s*(codex|openai|claude|anthropic)"
    + r"|\bai[- ]" + _gen + r"\b"
    + "|\U0001F916" + r"\s*" + _verbs
    + r"|(this\s+file\s+(was|is)\s+(" + _gen + r"|written|created)\s+by\s+(codex|openai|claude|anthropic|ai\b))",
    re.IGNORECASE,
)
# no-ai-attribution.sh anchors this pattern to the start of each line after
# stripping comment/quote/blockquote leaders, precisely so prose that merely
# discusses the rule is not flagged. A bare whole-content .search() here did
# not mirror that: writing any doc or script via heredoc that mentioned the
# phrase mid-sentence was blocked, while the same text through Write/Edit
# passed. Strip the same leaders and anchor the same way.
LEADER_RE = re.compile(r"^\s*(?:#|//|<!--|\*|-|>)+\s*")
QUOTE_RE = re.compile(r"^\s*[\"'`]+")
for _line in content.split("\n"):
    _stripped = QUOTE_RE.sub("", LEADER_RE.sub("", _line))
    if ATTRIBUTION_PATTERN.match(_stripped):
        findings.append("AI attribution phrase detected")
        break

if not findings:
    sys.exit(0)

lines = ["BLOCKED: content written via Bash (heredoc/redirect) failed the secret/AI-attribution scan.\n"]
for f in findings:
    lines.append(f"  - {f}")
lines.append("")
lines.append(
    "This mirrors no-secrets.sh and no-ai-attribution.sh, which only ever see\n"
    "Write/Edit tool_input - a heredoc or `echo ... > file` bypasses both.\n"
    "Never write real credentials or AI-attribution lines via Bash either."
)
msg = "\n".join(lines)
print(msg)
sys.stderr.write(msg + "\n")
sys.exit(2)
PYEOF

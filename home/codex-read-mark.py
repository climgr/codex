#!/usr/bin/env python3
"""Mark project specs read after a Codex file read or Bash read command."""

import json
import os
import re
import subprocess
import sys

try:
    payload = json.load(sys.stdin)
except (json.JSONDecodeError, OSError, UnicodeDecodeError):
    raise SystemExit(0)
if not isinstance(payload, dict):
    raise SystemExit(0)
tool_input = payload.get("tool_input") or {}
if not isinstance(tool_input, dict):
    raise SystemExit(0)
command = tool_input.get("command", "")
tool_name = payload.get("tool_name", "")
if not isinstance(tool_name, str):
    raise SystemExit(0)
is_bash = tool_name == "Bash"
is_file_read = tool_name == "Read" or re.search(
    r"(?:^|__)read(?:_|$)|^read(?:_|$)|readfile", tool_name, re.IGNORECASE
)
if not is_bash and not is_file_read:
    raise SystemExit(0)
response = payload.get("tool_response")
if is_file_read and isinstance(response, dict) and response.get("isError") is True:
    raise SystemExit(0)
if is_bash and (
    not isinstance(command, str)
    or not re.search(r"(?:^|[/\s\"'])(?:AI\.md|SPEC\.md)(?:$|[\s'\";|&])", command)
):
    raise SystemExit(0)
try:
    cwd = payload.get("cwd", os.getcwd())
    if not isinstance(cwd, str):
        raise SystemExit(0)
    project = subprocess.run(
        ["git", "-C", cwd, "rev-parse", "--show-toplevel"],
        check=True,
        capture_output=True,
        text=True,
        timeout=3,
    ).stdout.strip()
except (OSError, subprocess.SubprocessError):
    raise SystemExit(0)
if not project:
    raise SystemExit(0)

project = os.path.realpath(project)
spec_paths = {
    os.path.realpath(os.path.join(project, name)) for name in ("AI.md", "SPEC.md")
}
read_paths = set()
if is_bash:
    for path in spec_paths:
        if os.path.isfile(path) and re.search(
            r"(?:^|[/\s\"'])" + re.escape(os.path.basename(path)) + r"(?:$|[\s'\";|&])",
            command,
        ):
            read_paths.add(path)
else:
    for key in ("file_path", "filePath", "filepath", "path", "paths", "files"):
        value = tool_input.get(key)
        values = value if isinstance(value, list) else [value]
        for path in values:
            if isinstance(path, str) and path:
                resolved = os.path.realpath(
                    path if os.path.isabs(path) else os.path.join(cwd, path)
                )
                if resolved in spec_paths and os.path.isfile(resolved):
                    read_paths.add(resolved)

for path in read_paths:
    normalized = dict(payload)
    normalized["tool_name"] = "Read"
    normalized["tool_input"] = {"file_path": path}
    subprocess.run(
        [
            "bash",
            os.path.join(os.path.dirname(__file__), "hooks", "spec-guard-mark.sh"),
        ],
        input=json.dumps(normalized),
        text=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )

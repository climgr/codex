#!/usr/bin/env python3
"""Mark project specs read when a Codex Bash command explicitly reads them."""
import json
import os
import re
import subprocess
import sys

try:
    payload = json.load(sys.stdin)
except Exception:
    raise SystemExit(0)
if not isinstance(payload, dict):
    raise SystemExit(0)
tool_input = payload.get("tool_input") or {}
if not isinstance(tool_input, dict):
    raise SystemExit(0)
command = tool_input.get("command", "")
if not isinstance(command, str):
    raise SystemExit(0)
if not re.search(r"(?:^|[/\s])(?:AI\.md|SPEC\.md)(?:$|[\s'\";|&])", command):
    raise SystemExit(0)
try:
    project = subprocess.run(
        ["git", "-C", payload.get("cwd", os.getcwd()), "rev-parse", "--show-toplevel"],
        check=True, capture_output=True, text=True, timeout=3,
    ).stdout.strip()
except Exception:
    raise SystemExit(0)
if not project:
    raise SystemExit(0)
for name in ("AI.md", "SPEC.md"):
    path = os.path.join(project, name)
    if os.path.isfile(path) and re.search(r"(?:^|[/\s])" + re.escape(name) + r"(?:$|[\s'\";|&])", command):
        normalized = dict(payload)
        normalized["tool_name"] = "Read"
        normalized["tool_input"] = {"file_path": path}
        subprocess.run(
            ["bash", os.path.join(os.path.dirname(__file__), "hooks", "spec-guard-mark.sh")],
            input=json.dumps(normalized), text=True, stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, check=False,
        )

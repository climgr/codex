#!/usr/bin/env python3
"""Adapt Codex apply_patch hook input to the existing file-policy checks."""
import json
import os
import re
import subprocess
import sys

PRE_HOOKS = [
    "no-ai-attribution.sh",
    "no-secrets.sh",
    "no-forbidden-files.sh",
    "no-todo-comments.sh",
    "comment-placement-guard.sh",
    "spec-guard.sh",
]
POST_HOOKS = ["trailing-newline-guard.sh"]


def parse_patch(text):
    files = []
    current = None
    kind = None
    additions = []
    for line in text.splitlines():
        match = re.match(r"\*\*\* (Update|Add|Delete) File: (.+)$", line)
        if match:
            if current is not None:
                files.append((current, "\n".join(additions), kind))
            kind, current = match.group(1), match.group(2).strip()
            additions = []
            continue
        match = re.match(r"\*\*\* Move to: (.+)$", line)
        if match and current is not None:
            current = match.group(1).strip()
            continue
        if current is not None and line.startswith("+") and not line.startswith("+++"):
            additions.append(line[1:])
    if current is not None:
        files.append((current, "\n".join(additions), kind))
    return files


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0
    if not isinstance(payload, dict):
        return 0
    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        return 0
    patch = tool_input.get("command", "")
    if not isinstance(patch, str):
        return 0
    phase = os.environ.get("CODEX_HOOK_PHASE", "pre")
    hooks = PRE_HOOKS if phase == "pre" else POST_HOOKS
    root = os.path.dirname(os.path.abspath(__file__))
    for file_path, added, operation in parse_patch(patch):
        if file_path.startswith("/"):
            resolved = file_path
        else:
            resolved = os.path.normpath(os.path.join(payload.get("cwd", os.getcwd()), file_path))
        kind = "Write" if operation == "Add" else "Edit"
        normalized = dict(payload)
        normalized["tool_name"] = kind
        normalized["tool_input"] = {
            "file_path": resolved,
            "content": added,
            "new_string": added,
            "old_string": "",
        }
        encoded = json.dumps(normalized).encode()
        for hook in hooks:
            proc = subprocess.run(
                ["bash", os.path.join(root, "hooks", hook)],
                input=encoded,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            if proc.returncode == 2:
                sys.stdout.buffer.write(proc.stdout)
                sys.stderr.buffer.write(proc.stderr)
                return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

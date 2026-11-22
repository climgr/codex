"""Convert policy-hook denials into Codex's structured PreToolUse response."""

import json
import os
import signal
import shlex
import subprocess
import sys

HOOK_BYPASS_ALLOWED_HOOKS = {
    "drift-guard-read.sh",
    "enforce-doc-sync.sh",
    "enforce-test-lint-gate.sh",
    "validate-workflows.sh",
}


def emit_failure(hook_name, message):
    sys.stderr.write(f"{hook_name}: {message.rstrip()}\n")


def explicit_bypass_requested(payload, hook_name):
    try:
        event = json.loads(payload)
    except (TypeError, ValueError):
        return False
    if not isinstance(event, dict) or event.get("tool_name") != "Bash":
        return False
    tool_input = event.get("tool_input")
    if not isinstance(tool_input, dict):
        return False
    command = tool_input.get("command")
    if not isinstance(command, str):
        return False
    try:
        tokens = shlex.split(command, comments=True)
    except ValueError:
        return False
    return bool(
        hook_name in HOOK_BYPASS_ALLOWED_HOOKS
        and tokens
        and tokens[0] == "CODEX_HOOK_BYPASS=1"
    )


def main():
    if len(sys.argv) < 5 or sys.argv[3] != "--":
        emit_failure("pretool-hook-result", "invalid wrapper arguments")
        return 1

    hook_name = sys.argv[1]
    try:
        timeout_seconds = float(sys.argv[2])
    except ValueError:
        emit_failure(hook_name, "invalid timeout value")
        return 1
    if timeout_seconds <= 0:
        emit_failure(hook_name, "timeout must be positive")
        return 1

    hook_input = sys.stdin.buffer.read()
    if explicit_bypass_requested(hook_input, hook_name):
        return 0

    try:
        child = subprocess.Popen(
            sys.argv[4:],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True,
        )
        try:
            stdout, stderr = child.communicate(
                hook_input, timeout=timeout_seconds
            )
        except subprocess.TimeoutExpired:
            try:
                os.killpg(child.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                stdout, stderr = child.communicate(timeout=1)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(child.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                stdout, stderr = child.communicate()
            emit_failure(hook_name, f"timed out after {timeout_seconds:g} seconds")
            if stderr:
                sys.stderr.write(stderr.decode(errors="replace")[-8000:])
            return 1
    except OSError as error:
        emit_failure(hook_name, f"could not run hook: {error}")
        return 1

    stdout_text = stdout.decode(errors="replace")
    stderr_text = stderr.decode(errors="replace")
    reason = stderr_text.strip() or stdout_text.strip()
    if child.returncode == 2 and reason.lstrip().startswith("BLOCKED:"):
        if len(reason) > 8000:
            reason = reason[:4000] + "\n[reason truncated]\n" + reason[-4000:]
        response = {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": f"{hook_name}: {reason}",
            }
        }
        print(json.dumps(response))
        return 0

    if child.returncode != 0:
        detail = reason
        message = f"hook execution failed with exit code {child.returncode}"
        if detail:
            message += f": {detail[-8000:]}"
        emit_failure(hook_name, message)
        return child.returncode if child.returncode > 0 else 1

    sys.stdout.write(stdout_text)
    sys.stderr.write(stderr_text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

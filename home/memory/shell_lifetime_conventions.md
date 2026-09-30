---
name: Shell lifetime conventions
description: Timeout tiers, polling rules, background-process ownership, and follow-mode bounds for every shell command — enforced by bound-shell-lifetime.sh
type: user
---

Every shell command must be bounded to its operation — enforced by `bound-shell-lifetime.sh`.

## Timeout Tiers

- Lookups/status ≤60s · network/package ops ≤300s · builds/tests ≤600s; pass an explicit `timeout` on every Bash call sized to the tier
- **The Bash tool `timeout` parameter is in MILLISECONDS** — 60s = `60000`, 300s = `300000`, 600s = `600000`. Passing a seconds value (e.g. `30`) means 30 ms and kills the command instantly with exit 143 "timed out after 0s". Never pass a raw seconds number
- **600s (`600000`) is the Bash tool's hard maximum** — a command expected to exceed it must use run_in_background from the start (tracked, unbounded, notifies on exit)
- **After a timeout kill, never retry with the same value** — jump to the next tier or switch to run_in_background; repeated same-timeout retries waste tokens
- **After ANY timeout kill of a build or test, the ONLY allowed retry is run_in_background** — builds/tests already start at the top tier (600s), so there is no higher tier to jump to; never retry in the foreground, and never retry with a lower timeout (a command that outlived 600s will never finish in 300s)
- **First containerized build/test of a session is a cold cache** — image pull + dependency download + full compile; size it at 600s or run_in_background from the start, never a lower tier
- **Repeat runs scope to the failure** — after a partial pass, re-run only the failing package/module (`go test ./pkg/...`, `cargo test -p {crate}`), never the whole suite; never re-run a suite that already passed just to "check again"

## Polling and Waiting

- **Never poll for harness-tracked work** — subagents and background tasks deliver a task-notification on completion; a sentinel-file poll loop (`until [ -f *.done ]; do sleep N; done`) is forbidden — end the turn and let the notification resume it
- **Polling external state must be bounded** — wrap the loop in `timeout {n}` or add an iteration cap; `while true`/`until` + `sleep` with no bound is forbidden
- **No open-ended sleeps** — `sleep infinity` and any single sleep >600s are forbidden; for longer waits, end the turn or use a scheduler

## Detachment and Background Processes

- **No detachment** — `nohup`, `setsid`, `disown` escape both timeouts and task tracking; use run_in_background (tracked, notifies on exit, stoppable)
- **`&` requires ownership** — capture `PID=$!` at launch or close with `wait`; stop every background shell as soon as its output is consumed

## Follow Modes

- **Follow modes are bounded** — `tail -f` / `watch` only inside `timeout {n}`; otherwise read the file once

## Exemptions

- Anything already under `timeout {n}`
- Container-mediated payloads (container lifetime is governed by the Cleanup rules and `enforce-docker-rm.sh`)

#!/usr/bin/env python3
"""Classify direct or container/VM-mediated test and lint commands."""

import os
import shlex
import sys


SHELLS = {"bash", "sh", "zsh", "dash", "ksh", "fish"}
CONTAINERS = {"docker", "podman", "nerdctl"}


def unwrap(argv):
    args = list(argv)
    while args:
        name = os.path.basename(args[0]).lstrip("\\")
        if name in {"command", "builtin", "exec", "time", "nohup"}:
            args.pop(0)
            while args and args[0].startswith("-"):
                args.pop(0)
            continue
        if name == "env":
            args.pop(0)
            while args and (args[0].startswith("-") or "=" in args[0]):
                args.pop(0)
            continue
        if name == "timeout":
            args.pop(0)
            while args and args[0].startswith("-"):
                args.pop(0)
            if args:
                args.pop(0)
            continue
        if name in SHELLS:
            for index, token in enumerate(args[1:], 1):
                if token in {"-c", "--command"} and index + 1 < len(args):
                    return unwrap(shlex.split(args[index + 1]))
                if token.startswith("-") and not token.startswith("--") and "c" in token[1:] and index + 1 < len(args):
                    return unwrap(shlex.split(args[index + 1]))
                if token.startswith("--command="):
                    return unwrap(shlex.split(token.split("=", 1)[1]))
            return args
        if name in CONTAINERS and len(args) > 1:
            subcommand, rest = args[1], args[2:]
            if subcommand == "run":
                value_flags = {
                    "-v", "--volume", "-e", "--env", "-w", "--workdir", "--name",
                    "--network", "--memory", "--cpus", "--user", "--entrypoint",
                    "--mount", "-p", "--publish", "--platform",
                }
                index = 0
                while index < len(rest):
                    token = rest[index]
                    if token == "--":
                        index += 1
                        break
                    if token in value_flags:
                        index += 2
                    elif token.startswith("-"):
                        index += 1
                    else:
                        index += 1
                        break
                return unwrap(rest[index:])
            if subcommand == "exec":
                index = 0
                while index < len(rest) and rest[index].startswith("-"):
                    index += 2 if rest[index] in {"-u", "--user", "-w", "--workdir", "--env"} else 1
                if index < len(rest):
                    index += 1
                if index < len(rest) and rest[index] == "--":
                    index += 1
                return unwrap(rest[index:])
            if subcommand == "compose" and len(rest) >= 2 and rest[0] in {"run", "exec"}:
                tail = rest[1:]
                value_flags = {"-e", "--env", "-u", "--user", "-w", "--workdir", "-v", "--volume"}
                while tail and tail[0].startswith("-"):
                    option = tail.pop(0)
                    if option in value_flags and tail:
                        tail.pop(0)
                if tail:
                    tail.pop(0)
                return unwrap(tail)
            return args
        if name in {"incus", "lxc"} and len(args) > 2 and args[1] == "exec":
            rest = args[2:]
            index = 1
            value_flags = {"--cwd", "--env", "--user", "--mode", "--group"}
            while index < len(rest) and rest[index] != "--":
                if rest[index] in value_flags:
                    index += 2
                elif rest[index].startswith("-"):
                    index += 1
                else:
                    return unwrap(rest[index:])
            if index < len(rest):
                index += 1
            return unwrap(rest[index:])
        if name == "ssh" and len(args) > 2:
            index = 1
            value_flags = {"-p", "-i", "-l", "-o", "-F", "-J"}
            while index < len(args) and args[index].startswith("-"):
                index += 2 if args[index] in value_flags else 1
            index += 1
            remote = args[index:]
            if len(remote) == 1:
                remote = shlex.split(remote[0])
            return unwrap(remote)
        return args
    return []


def classify(argv):
    args = unwrap(argv)
    if not args:
        return set()
    raw_cmd = args[0].lstrip("\\")
    cmd = os.path.basename(raw_cmd)
    rest = args[1:]
    if any(part in {"--help", "-h", "--version", "-V", "-version"} for part in rest):
        return set()
    result = set()

    if cmd in {"make", "gmake"} and rest and rest[0] in {"test", "check"}:
        result.add("test")
    if cmd in {"make", "gmake"} and rest and rest[0] in {"lint", "check"}:
        result.add("lint")

    if (cmd == "go" and rest[:1] == ["test"]
            or cmd == "cargo" and rest[:1] in (["test"], ["nextest"])
            or cmd in {"pytest", "py.test", "unittest", "tox", "nox", "rspec", "phpunit", "ctest"}
            and rest[:1] not in (["--version"], ["--help"])
            or cmd == "bundle" and rest[:2] == ["exec", "rspec"]
            or cmd in {"python", "python3"} and rest[:2] == ["-m", "pytest"]
            and rest[2:3] not in (["--version"], ["--help"])
            or cmd in {"python", "python3"} and rest[:2] == ["-m", "unittest"]
            or cmd == "jq" and rest[:1] == ["empty"]
            or cmd in {"swift", "flutter", "dart", "dotnet", "mix"} and rest[:1] == ["test"]
            or cmd in {"npm", "yarn", "pnpm"} and (rest[:1] == ["test"] or rest[:2] == ["run", "test"])
            or cmd == "npx" and rest[:1] in (["vitest"], ["jest"])
            or cmd == "bun" and rest[:1] == ["test"]
            or cmd == "deno" and rest[:1] == ["test"]
            or cmd == "gradle" and "test" in rest
            or raw_cmd in {"./gradlew", "gradlew"} and "test" in rest
            or cmd == "mvn" and any(part.startswith("test") for part in rest)
            or cmd == "rake" and rest[:1] == ["test"]
            or cmd == "composer" and rest[:1] == ["test"]):
        result.add("test")
    if cmd in {"bash", "sh"} and rest[:1] == ["-n"]:
        result.add("test")
    if cmd in {"python", "python3"} and rest[:2] == ["-m", "py_compile"]:
        result.add("test")

    if (cmd == "go" and rest[:1] == ["vet"]
            or cmd == "cargo" and (rest[:1] == ["clippy"] or rest[:1] == ["fmt"] and "--check" in rest)
            or cmd == "ruff" and (rest[:1] == ["check"] or rest[:2] == ["format", "--check"])
            or cmd == "golangci-lint" and rest[:1] == ["run"]
            or cmd == "taplo" and rest[:1] == ["lint"]
            or cmd in {"mypy", "pyright", "bandit", "swiftlint", "shellcheck", "clang-tidy",
                       "cppcheck", "rubocop", "phpcs", "php-cs-fixer", "phpstan", "rpmlint",
                       "lintian", "namcap", "apkbuild-lint", "statix", "appimagelint",
                       "script-lint", "go-lint", "rust-lint"}
            or cmd == "brew" and rest[:1] in (["audit"], ["style"])
            or cmd == "snapcraft" and rest[:1] == ["lint"]
            or cmd == "flatpak-builder-lint"
            or cmd == "nix" and rest[:2] == ["flake", "check"]
            or cmd == "npx" and (rest[:1] == ["eslint"] or rest[:2] == ["prettier", "--check"])
            or cmd in {"npm", "yarn", "pnpm"} and rest[:2] == ["run", "lint"]
            or cmd == "gradle" and any(part in {"lint", "ktlintCheck", "detekt"} for part in rest)
            or raw_cmd in {"./gradlew", "gradlew"} and any(part in {"lint", "ktlintCheck", "detekt"} for part in rest)
            or cmd == "mvn" and any("checkstyle:check" in part or "spotbugs:check" in part for part in rest)
            or cmd in {"flutter", "dart"} and rest[:1] == ["analyze"]
            or cmd == "dotnet" and rest[:2] == ["format", "--verify-no-changes"]
            or cmd == "mix" and (rest[:1] == ["credo"] or rest[:2] == ["format", "--check-formatted"])):
        result.add("lint")
    return result


try:
    gates = classify(sys.argv[1:])
except (IndexError, ValueError):
    gates = set()
print(" ".join(sorted(gates)))

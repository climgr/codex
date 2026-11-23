#!/usr/bin/env python3
"""Classify direct or container/VM-mediated test and lint commands."""

import os
import shlex
import sys

SHELLS = {"bash", "sh", "zsh", "dash", "ksh", "fish"}
CONTAINERS = {"docker", "podman", "nerdctl", "docker-compose", "podman-compose"}
BUILD_TOOLS = {"bazel", "bazelisk", "buck", "buck2", "pants", "ninja", "meson"}
TEST_RUNNERS = {
    "pytest",
    "py.test",
    "unittest",
    "tox",
    "nox",
    "nose2",
    "rspec",
    "spec",
    "phpunit",
    "pest",
    "ctest",
    "jest",
    "vitest",
    "mocha",
    "ava",
    "tap",
    "playwright",
    "cypress",
    "nightwatch",
    "karma",
    "webdriver",
    "robot",
    "behave",
    "cargo-nextest",
}
LINTERS = {
    "mypy",
    "pyright",
    "basedpyright",
    "pytype",
    "bandit",
    "pylint",
    "flake8",
    "ruff",
    "swiftlint",
    "shellcheck",
    "clang-tidy",
    "cppcheck",
    "cpplint",
    "golangci-lint",
    "staticcheck",
    "revive",
    "errcheck",
    "ineffassign",
    "gosec",
    "rubocop",
    "standardrb",
    "phpcs",
    "php-cs-fixer",
    "phpstan",
    "psalm",
    "eslint",
    "biome",
    "stylelint",
    "htmlhint",
    "markdownlint",
    "vale",
    "yamllint",
    "actionlint",
    "hadolint",
    "checkov",
    "tfsec",
    "trivy",
    "semgrep",
    "gitleaks",
    "taplo",
    "typos",
    "codespell",
    "shellharden",
    "statix",
    "appimagelint",
    "rpmlint",
    "lintian",
    "namcap",
    "apkbuild-lint",
    "script-lint",
    "go-lint",
    "rust-lint",
    "ansible-lint",
    "cfn-lint",
    "kubeconform",
    "kubeval",
    "checkmake",
}


def container_subcommand(rest):
    """Return a container CLI subcommand after its global options."""
    value_flags = {
        "--config",
        "--context",
        "--host",
        "--log-level",
        "-H",
        "--url",
        "--connection",
        "--identity",
        "--namespace",
        "--snapshotter",
        "--address",
        "--data-root",
        "--storage-driver",
        "--project-name",
        "--project-directory",
        "--env-file",
        "--file",
        "-f",
        "--profile",
    }
    index = 0
    while index < len(rest):
        token = rest[index]
        if token in value_flags:
            index += 2
        elif token.startswith("-"):
            index += 1
        else:
            return rest[index:]
    return []


def unwrap(argv):
    args = list(argv)
    while args:
        name = os.path.basename(args[0]).lstrip("\\")
        if name in {
            "command",
            "builtin",
            "exec",
            "time",
            "nohup",
            "nice",
            "ionice",
            "stdbuf",
        }:
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
        if name in {"sudo", "doas"}:
            args.pop(0)
            while args and args[0].startswith("-"):
                option = args.pop(0)
                if option in {"-u", "-g", "-h", "-p", "-C", "-T"} and args:
                    args.pop(0)
            continue
        if (
            name in {"uv", "poetry", "pipenv", "pdm", "hatch", "pipx"}
            and len(args) > 1
            and args[1] in {"run", "exec", "test"}
        ):
            args = args[2:]
            if args[:1] == ["--"]:
                args.pop(0)
            continue
        if name in SHELLS:
            for index, token in enumerate(args[1:], 1):
                if token in {"-c", "--command"} and index + 1 < len(args):
                    return args
                if (
                    token.startswith("-")
                    and not token.startswith("--")
                    and "c" in token[1:]
                    and index + 1 < len(args)
                ):
                    return args
                if token.startswith("--command="):
                    return args
            return args
        if name in CONTAINERS and len(args) > 1:
            subcommand, rest = args[1], args[2:]
            if name in {"docker-compose", "podman-compose"} and subcommand in {
                "run",
                "exec",
            }:
                value_flags = {
                    "-e",
                    "--env",
                    "-u",
                    "--user",
                    "-w",
                    "--workdir",
                    "-v",
                    "--volume",
                }
                while rest and rest[0].startswith("-"):
                    option = rest.pop(0)
                    if option in value_flags and rest:
                        rest.pop(0)
                if rest:
                    rest.pop(0)
                return unwrap(rest)
            if subcommand == "run":
                value_flags = {
                    "-v",
                    "--volume",
                    "-e",
                    "--env",
                    "-w",
                    "--workdir",
                    "--name",
                    "--network",
                    "--memory",
                    "--cpus",
                    "--user",
                    "--entrypoint",
                    "--mount",
                    "-p",
                    "--publish",
                    "--platform",
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
                    index += (
                        2
                        if rest[index] in {"-u", "--user", "-w", "--workdir", "--env"}
                        else 1
                    )
                if index < len(rest):
                    index += 1
                if index < len(rest) and rest[index] == "--":
                    index += 1
                return unwrap(rest[index:])
            if (
                subcommand == "compose"
                and len(rest) >= 2
                and rest[0] in {"run", "exec"}
            ):
                tail = rest[1:]
                value_flags = {
                    "-e",
                    "--env",
                    "-u",
                    "--user",
                    "-w",
                    "--workdir",
                    "-v",
                    "--volume",
                }
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
    if cmd in SHELLS:
        for index, token in enumerate(rest):
            if token in {"-c", "--command"} and index + 1 < len(rest):
                shell_text = rest[index + 1]
            elif token.startswith("--command="):
                shell_text = token.split("=", 1)[1]
            elif (
                token.startswith("-")
                and not token.startswith("--")
                and "c" in token[1:]
                and index + 1 < len(rest)
            ):
                shell_text = rest[index + 1]
            else:
                continue
            lexer = shlex.shlex(shell_text, posix=True, punctuation_chars=";&|")
            lexer.whitespace_split = True
            lexer.commenters = ""
            parts = list(lexer)
            gates = set()
            segment = []
            for part in parts:
                if part in {"&&", "||", ";", "|", "&"}:
                    if segment:
                        gates.update(classify(segment))
                        segment = []
                else:
                    segment.append(part)
            if segment:
                gates.update(classify(segment))
            return gates
    if any(part in {"--help", "-h", "--version", "-V", "-version"} for part in rest):
        return set()
    result = set()

    first = rest[0] if rest else ""
    command_label = cmd
    if cmd in SHELLS and first and not first.startswith("-"):
        command_label = os.path.basename(first).lower()

    # Conventional validation command names and subcommands cover project
    # scripts and tools that are not in the explicit language/tool lists.
    label_parts = set(command_label.replace(".", "-").replace("_", "-").split("-"))
    if command_label not in {"test", "[", "true", "echo"} and label_parts & {
        "test",
        "tests",
        "spec",
        "specs",
    }:
        result.add("test")
    if label_parts & {"lint", "linter", "checkstyle"}:
        result.add("lint")
    if (
        first in {"test", "tests", "spec", "specs", "validate", "verify", "build"}
        or first in {"check", "check-all"}
        and cmd not in (LINTERS | {"biome"})
    ):
        result.add("test")
    if (
        first in {"lint", "lint-all", "typecheck", "check-types"}
        or first in {"check", "check-all"}
        and cmd != "cargo"
        and cmd not in (LINTERS | {"biome"})
    ):
        result.add("lint")

    # Project task runners expose conventional validation target names.
    if cmd in {"make", "gmake", "just", "task", "invoke"}:
        targets = set(rest)
        if targets & {"test", "tests", "check", "check-all", "validate", "verify"}:
            result.add("test")
        if targets & {"lint", "lint-all", "check", "check-all", "format-check"}:
            result.add("lint")
        if targets & {"build", "build-all", "package"}:
            result.add("test")

    # Container image builds validate the Dockerfile and the complete build
    # context, whether they use the classic, Buildx, Compose, or Buildah form.
    if cmd in CONTAINERS:
        container_args = container_subcommand(rest)
        if (
            container_args[:1] == ["build"]
            or container_args[:2] == ["buildx", "build"]
            or container_args[:2] == ["buildx", "bake"]
            or container_args[:2] == ["compose", "build"]
            or container_args[:1] == ["up"]
            and "--build" in container_args
            or container_args[:2] == ["compose", "up"]
            and "--build" in container_args
        ):
            result.add("test")
        if container_args[:1] == ["config"] or container_args[:2] == [
            "compose",
            "config",
        ]:
            result.add("test")
    if cmd == "buildah" and first in {"bud", "build"}:
        result.add("test")
    if cmd == "buildctl" and first == "build":
        result.add("test")
    if cmd in {"kaniko", "executor"} and any(
        part.startswith("--dockerfile") for part in rest
    ):
        result.add("test")

    # General test runners and language-native test commands.
    if cmd in TEST_RUNNERS:
        result.add("test")
    if cmd == "go" and first == "test":
        result.add("test")
    if cmd == "go" and rest[:2] == ["mod", "verify"]:
        result.add("test")
    if cmd == "cargo" and (first == "test" or rest[:2] == ["nextest", "run"]):
        result.add("test")
    if cmd == "cargo" and first == "check":
        result.add("test")
    if cmd == "xcodebuild" and first == "test":
        result.add("test")
    if (
        cmd in {"swift", "flutter", "dart", "dotnet", "mix", "deno", "bun"}
        and first == "test"
        or cmd == "xcodebuild"
        and "test" in rest
    ):
        result.add("test")
    if cmd in {"npm", "yarn", "pnpm", "bun"} and rest[:2] == ["run", "check"]:
        result.add("test")
    if cmd in {"npm", "yarn", "pnpm", "bun"} and (
        first.startswith("test:")
        or first == "test"
        or rest[:2] == ["run", "test"]
        or len(rest) > 1
        and rest[1].startswith("test:")
    ):
        result.add("test")
    if cmd in {"npx", "bunx"} and first in TEST_RUNNERS:
        result.add("test")
    if cmd in {"npm", "yarn", "pnpm", "bun"} and first in {"exec", "dlx"}:
        tool_index = 1
        if rest[tool_index : tool_index + 1] == ["--"]:
            tool_index += 1
        tool = rest[tool_index] if len(rest) > tool_index else ""
        if tool in TEST_RUNNERS:
            result.add("test")
        if (
            tool in LINTERS
            or tool == "prettier"
            and "--check" in rest[tool_index + 1 :]
        ):
            result.add("lint")
    if (
        cmd == "coverage"
        and first == "run"
        and any(
            part in TEST_RUNNERS or part in {"pytest", "unittest"} for part in rest[1:]
        )
    ):
        result.add("test")
    if cmd == "node" and (first == "--test" or first == "--test-reporter"):
        result.add("test")
    if cmd in {"python", "python3", "pypy", "pypy3"} and (
        rest[:2]
        in (["-m", "pytest"], ["-m", "unittest"], ["-m", "nose2"], ["-m", "doctest"])
    ):
        result.add("test")
    if cmd == "jq" and first == "empty":
        result.add("test")
    if cmd in ({"gradle", "sbt"} | BUILD_TOOLS) and any(
        part in {"test", "check", "verify", "testOnly", "testCompile"}
        or part.startswith("test")
        for part in rest
    ):
        result.add("test")
    if raw_cmd in {"./gradlew", "gradlew", "./mvnw", "mvnw"} and any(
        part in {"test", "check", "verify", "testOnly", "testCompile"} for part in rest
    ):
        result.add("test")
    if cmd == "mvn" and any(part.startswith(("test", "verify")) for part in rest):
        result.add("test")
    if cmd == "bundle" and rest[:2] == ["exec", "rspec"]:
        result.add("test")
    if cmd == "bundle" and rest[:2] == ["exec", "rubocop"]:
        result.add("lint")
    if cmd == "rake" and first in {"test", "spec"}:
        result.add("test")
    if cmd == "php" and rest[:2] == ["artisan", "test"]:
        result.add("test")
    if cmd == "composer" and (
        first == "test" or first == "run-script" and "test" in rest[1:]
    ):
        result.add("test")
    if cmd in {"bash", "sh", "dash", "zsh"} and first == "-n":
        result.add("test")
    if cmd in {"python", "python3"} and rest[:2] == ["-m", "py_compile"]:
        result.add("test")
    if cmd in {"python", "python3"} and rest[:2] == ["-m", "compileall"]:
        result.add("test")
    if (
        cmd in {"python", "python3"}
        and len(rest) > 1
        and rest[0] == "-m"
        and rest[1] in LINTERS
    ):
        result.add("lint")
    if cmd in {"ruby", "perl"} and first in {"-c", "--check"}:
        result.add("test")
    if cmd in {"node", "deno", "bun"} and first == "--check":
        result.add("test")
    if cmd in {"gcc", "g++", "clang", "clang++"} and "-fsyntax-only" in rest:
        result.add("test")

    # Common build and package checks are treated as test-gate validation.
    if (
        cmd in {"go", "cargo", "swift", "flutter", "dotnet", "gradle", "sbt", "nix"}
        and first == "build"
    ):
        result.add("test")
    if cmd in {"gradle", "sbt", "xcodebuild"} and any(
        part in {"assemble", "compile", "package", "build", "archive"}
        or part.startswith(("assemble", "compile"))
        for part in rest
    ):
        result.add("test")
    if cmd in BUILD_TOOLS and first in {"build", "compile", "package"}:
        result.add("test")
    if cmd in {"npm", "yarn", "pnpm", "bun"} and (
        first == "build" or rest[:2] == ["run", "build"]
    ):
        result.add("test")
    if cmd in {"cmake", "ninja"} and (first == "--build" or first == "build"):
        result.add("test")
    if cmd == "terraform" and first == "validate":
        result.add("test")
    if cmd == "helm" and first in {"lint", "template"}:
        result.add("test")
    if cmd == "packer" and first == "validate":
        result.add("test")
    if cmd in {"mvn", "./mvnw", "mvnw"} and any(
        part in {"validate", "package", "verify", "install", "compile"} for part in rest
    ):
        result.add("test")
    if raw_cmd in {"./gradlew", "gradlew"} and any(
        part in {"build", "assemble", "check", "assembleDebug", "assembleRelease"}
        or part.startswith(("assemble", "compile"))
        for part in rest
    ):
        result.add("test")
    if cmd == "nix" and rest[:1] == ["build"]:
        result.add("test")

    # Linter executables, standard linter subcommands, and format checks.
    if cmd in LINTERS:
        result.add("lint")
    if cmd == "prettier" and "--check" in rest:
        result.add("lint")
    if cmd == "biome" and first in {"check", "lint"}:
        result.add("lint")
    if cmd in {"npx", "bunx"} and first == "prettier" and "--check" in rest:
        result.add("lint")
    if cmd in {"shfmt", "swiftformat"} and any(
        part in {"--diff", "--lint", "--check"} for part in rest
    ):
        result.add("lint")
    if cmd == "isort" and "--check-only" in rest:
        result.add("lint")
    if cmd == "black" and "--check" in rest:
        result.add("lint")
    if cmd == "autopep8" and "--diff" in rest:
        result.add("lint")
    if cmd == "git" and rest[:2] == ["diff", "--check"]:
        result.add("lint")
    if cmd == "pre-commit" and first == "run":
        result.add("lint")
    if cmd == "cargo" and first in {"audit", "deny"}:
        result.add("lint")
    if cmd == "go" and first == "vet":
        result.add("lint")
    if cmd == "cargo" and (first == "clippy" or first == "fmt" and "--check" in rest):
        result.add("lint")
    if cmd == "ruff" and (first == "check" or rest[:2] == ["format", "--check"]):
        result.add("lint")
    if cmd in {"tsc", "vue-tsc"} and "--noEmit" in rest:
        result.add("lint")
    if cmd == "svelte-check" and "--fail-on-warnings" in rest:
        result.add("lint")
    if cmd == "taplo" and first in {"lint", "check"}:
        result.add("lint")
    if cmd == "nix" and rest[:2] == ["flake", "check"]:
        result.add("lint")
    if cmd in {"npx", "bunx"} and first in LINTERS:
        result.add("lint")
    if cmd in {"npm", "yarn", "pnpm", "bun"} and (
        rest[:2] == ["run", "lint"]
        or first in {"lint", "lint:check", "typecheck", "check-types"}
        or rest[:2] == ["run", "check"]
        or len(rest) > 1
        and rest[1] in {"lint", "typecheck", "check-types"}
    ):
        result.add("lint")
    if cmd in ({"gradle", "sbt"} | BUILD_TOOLS) and any(
        part in {"lint", "ktlintCheck", "detekt", "spotlessCheck", "checkstyleMain"}
        for part in rest
    ):
        result.add("lint")
    if raw_cmd in {"./gradlew", "gradlew", "./mvnw", "mvnw"} and any(
        part in {"lint", "ktlintCheck", "detekt", "spotlessCheck", "checkstyle:check"}
        for part in rest
    ):
        result.add("lint")
    if cmd == "mvn" and any(
        "checkstyle:check" in part or "spotbugs:check" in part or "pmd:check" in part
        for part in rest
    ):
        result.add("lint")
    if cmd in {"flutter", "dart"} and first == "analyze":
        result.add("lint")
    if cmd == "dotnet" and first == "format" and "--verify-no-changes" in rest:
        result.add("lint")
    if cmd == "mix" and (
        first == "credo" or rest[:2] == ["format", "--check-formatted"]
    ):
        result.add("lint")
    if cmd == "terraform" and first == "fmt" and "-check" in rest:
        result.add("lint")
    if cmd == "helm" and first == "lint":
        result.add("lint")
    if cmd in {"kubectl", "kustomize"} and any(
        part.startswith("--dry-run") or part == "--validate=true" for part in rest
    ):
        result.add("test")
    if cmd in {"php", "php8", "php8.1", "php8.2", "php8.3", "php8.4"} and first == "-l":
        result.add("test")
    if cmd == "php" and first == "-l":
        result.add("lint")
    if cmd == "brew" and first in {"audit", "style"}:
        result.add("lint")
    if (cmd == "snapcraft" and first == "lint") or cmd == "flatpak-builder-lint":
        result.add("lint")
    return result


try:
    gates = classify(sys.argv[1:])
except (IndexError, ValueError):
    gates = set()
print(" ".join(sorted(gates)))

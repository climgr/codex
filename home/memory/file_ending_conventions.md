---
name: File ending conventions
description: Every text file ends with a single trailing newline; exceptions for raw-value secret/token files, verbatim-interpolated files, mid-line fragments, and binary/generated artifacts
type: user
---

# File Ending Conventions

## Rule

Every text file ends with a single trailing newline (`\n` as the
last byte — "press Enter after the last line"). This is the POSIX
definition of a text file; git, diff, cat, and most linters expect
it.

- Exactly ONE trailing newline — never blank lines at EOF
- Applies to all created and edited text files: code, configs,
  Markdown, YAML, JSON, TOML, `.env`, PEM keys, scripts, CSV
- When editing an existing file that is missing it, add it as part
  of the edit (counts as formatting, not scope expansion)

## Exceptions — NO trailing newline

Files whose entire content is consumed as a raw value, where the
`\n` becomes part of the data and corrupts it:

| Type | Why |
|---|---|
| Single-value secret/token files (`*.token`, `.password`, htpasswd input fragments, Docker/K8s secret files mounted as raw values) | `\n` becomes part of the credential |
| Files interpolated verbatim into strings by strict tooling (e.g. a `VERSION` file read with no trimming) | `\n` leaks into version strings, headers, tags |
| Fragment files concatenated mid-line into another file (SSI-style includes, template partials spliced inline) | `\n` breaks the surrounding line |
| Binary files and generated artifacts (images, archives, minified bundles, lockfiles owned by tooling) | never touch endings; the generator owns the format |

When a project's own tooling (formatter, linter, generator) enforces
a different ending for a specific filetype, the project tool wins —
never fight the formatter.

## Verification

Check the last byte before assuming:

```sh
# empty output = has trailing newline; "missing" = does not
tail -c 1 -- "$f" | od -An -c | grep -q '\\n' || echo missing
```

Fix by appending exactly one newline:

```sh
tail -c 1 -- "$f" | od -An -c | grep -q '\\n' || printf '\n' >> "$f"
```

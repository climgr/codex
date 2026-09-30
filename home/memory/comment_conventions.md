---
name: Comment conventions
description: Comment placement, formats where comments are forbidden, and language-specific comment syntax rules
type: user
---

## Placement

**Comments always ABOVE, never inline** — every comment goes on its own line above the code it describes; never append a comment to the end of a code line. Single line, ≤180 characters. Applies to all languages.

Exceptions:
- Tool-required directives that the linter/type-checker must see on the same line (`# noqa`, `# type: ignore`, `// nolint`) are allowed inline, but an explanatory comment on the line above is still required when the reason is not obvious.
- CI workflow SHA-pin version annotations stay inline — `uses: owner/action@{40-char-sha}  # vX.Y.Z` — Renovate reads and rewrites the same-line comment when bumping pins; never move it above the `uses:` line.

## Formats Where Comments Are Never Valid

- JSON (`.json`, `package.json`, `tsconfig.json`, etc.) — JSON has no comment syntax; comments break parsers and validators; use a separate doc file instead
- `.env` / `app.env` / `default.env` KEY=VALUE files — comment lines (`# ...`) are tolerated by some parsers but must never appear in files read by strict parsers (Docker, some CI tools)
- CSV/TSV and other pure data formats
- Any binary or compiled artifact

## Language Syntax Rules

**JavaScript and CSS must always parse valid** — comments are allowed (placement rule applies) but only in valid syntax: JS uses `//` or `/* */`; CSS uses `/* */` only — `//` and `#` are invalid in CSS and break the stylesheet. Never place a comment where it breaks parsers or minifiers (inside a CSS value, mid-selector, inside a template literal placeholder).

---
name: Image conventions
description: Rules for converting, sizing, and viewing images and screenshots — context efficiency, tool fallback chain, URL viewing workflow
type: user
---

## Core Rules

- **Always convert images before reading** — never load a raw screenshot or downloaded image directly. Convert to the smallest readable size first.
- **Maximum size: 1280px on the longest side** — sufficient for Codex to inspect UI; larger is wasteful context.
- **Target format: WebP** — best compression at quality. Fallback chain if the tool cannot produce WebP: JPEG → PNG → original as-is.
- **Never embed originals** — if conversion is possible, only the converted file is read. The original stays in the tempdir.

## Tool Fallback Chain

Check in order; use the first available:

1. **ImageMagick `convert`** — preferred:
   ```bash
   convert input.png -resize '1280x1280>' -quality 80 output.webp
   ```
2. **`ffmpeg`** — if ImageMagick is absent:
   ```bash
   ffmpeg -i input.png -vf "scale='if(gt(iw,ih),1280,-1)':'if(gt(ih,iw),1280,-1)'" -quality 80 output.webp
   ```
3. **`vips`** — if ffmpeg is also absent:
   ```bash
   vips thumbnail input.png output.webp 1280
   ```
4. **Original as-is** — if none of the above are installed: read the original file unchanged. Note the missing tools but do not fail.

Always fall back gracefully — the absence of a tool is not a blocking error.

## URL / Remote Image Viewing Workflow

When asked to view an image or screenshot at a URL:

1. **Create a tempdir** — follow `~/.codex/memory/tempdir_conventions.md` (`{project_org}/{internal_name}-XXXXXX` pattern).
2. **curl the URL** — use curl defaults: `curl -q -LSsf {url} -o {tempdir}/original.{ext}`
3. **Convert** — apply the fallback chain above; output to `{tempdir}/view.webp` (or `.jpg`/`.png` as determined by the chain).
4. **Read the converted file** — use the Read tool on the converted path.
5. **Cleanup** — remove the tempdir after reading (guarded: `[ -n "$TMPDIR_PATH" ] && rm -rf "$TMPDIR_PATH"`).

```bash
# Full example — substitute {project_org}/{internal_name} from IDEA.md; never hardcode
mkdir -p "${TMPDIR:-/tmp}/${PROJECT_ORG}"
_tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/${PROJECT_ORG}/${INTERNAL_NAME}-XXXXXX")
curl -q -LSsf "https://example.com/screenshot.png" -o "${_tmpdir}/original.png"
convert "${_tmpdir}/original.png" -resize '1280x1280>' -quality 80 "${_tmpdir}/view.webp" 2>/dev/null \
  || ffmpeg -i "${_tmpdir}/original.png" -vf "scale='if(gt(iw,ih),1280,-1)':'if(gt(ih,iw),1280,-1)'" -quality 80 "${_tmpdir}/view.webp" 2>/dev/null \
  || vips thumbnail "${_tmpdir}/original.png" "${_tmpdir}/view.webp" 1280 2>/dev/null \
  || cp "${_tmpdir}/original.png" "${_tmpdir}/view.webp"
# Read ${_tmpdir}/view.webp via the Read tool
[ -n "${_tmpdir}" ] && rm -rf "${_tmpdir}"
```

## Local Screenshot / File Viewing

Same workflow, skipping the curl step:

1. Create a tempdir.
2. Copy or link the source file into the tempdir.
3. Convert using the fallback chain.
4. Read the converted file.
5. Cleanup.

## AI Rules

- **Never skip conversion for context-efficiency** — a 4 MB PNG is wasteful even if it "works".
- **Never use a pinned tool** — always try the full fallback chain so the workflow succeeds on any host.
- **Tempdir is mandatory** — do not convert in-place or write to the source directory. Follow `~/.codex/memory/tempdir_conventions.md` for path structure and permissions.
- **Tempdir permissions** — create with mode `0700`; intermediate image files may contain embedded metadata or be derived from sensitive screenshots. Never use `0755` for image tempdirs.
- **Clean up immediately** — remove the tempdir (original + converted files) as soon as the Read tool call completes. Use the guarded form: `[ -n "$_tmpdir" ] && rm -rf "$_tmpdir"`.
- **Document missing tools** — if none of the conversion tools are present, note which tools were tried and that the original was used.

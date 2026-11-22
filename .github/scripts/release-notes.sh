#!/usr/bin/env bash
# Builds the GitHub Release text for one version of CodeNote Online.
# Usage: .github/scripts/release-notes.sh 2.0.2 > notes.md
set -euo pipefail
VERSION="$1"
REPO="${GITHUB_REPOSITORY:-mahmoudyosrimahmoud13/code_note}"
BASE="https://github.com/$REPO/releases/download/v$VERSION"

# The changelog section for this version (between its heading and the next one).
CHANGES=$(awk -v v="$VERSION" '
  $0 ~ "^## \\[" v "\\]" {found=1; next}
  found && /^## \[/ {exit}
  found {print}
' CHANGELOG.md)
if [ -z "$(echo "$CHANGES" | tr -d '[:space:]')" ]; then
  CHANGES="See [CHANGELOG.md](https://github.com/$REPO/blob/v$VERSION/CHANGELOG.md)."
fi

# One download table per build. $1 = file name start, $2 = app name.
table() {
  local F="$1-$VERSION"
  cat <<TABLE
| Platform | File | How to install |
| --- | --- | --- |
| Android 7.0+ | [$F-android.apk]($BASE/$F-android.apk) | Open the file on your phone and tap Install. Updates install over the old version. |
| Windows 10/11 | [$F-windows-x64.zip]($BASE/$F-windows-x64.zip) | Unzip, then run \`code_note.exe\`. If SmartScreen warns, click More info > Run anyway. |
| Ubuntu, Debian, Mint, Zorin | [$F-linux-amd64.deb]($BASE/$F-linux-amd64.deb) | \`sudo apt install ./$F-linux-amd64.deb\`, then open $2 from the app menu. |
| Other Linux | [$F-linux-x64.tar.gz]($BASE/$F-linux-x64.tar.gz) | Extract, then run \`./code_note\` (needs GTK 3). |
| macOS 10.15+ | [$F-macos.zip]($BASE/$F-macos.zip) | Unzip and move to Applications. The first time, right-click the app > Open (it isn't notarized). |
TABLE
}

cat <<NOTES
## CodeNote Online $VERSION

CodeNote with accounts, chat and notes sync. Two builds of the same app:
**CodeNote Online** runs on Supabase, **CodeNote Server** runs on your own FastAPI server.
$CHANGES

## Download: CodeNote Online (Supabase)

$(table CodeNote-Online "CodeNote Online")

## Download: CodeNote Server (your FastAPI server)

The first time it opens, it asks for your server's address.

$(table CodeNote-Server "CodeNote Server")

## For the backends

- **FastAPI server:** [CodeNote-server-$VERSION.zip]($BASE/CodeNote-server-$VERSION.zip). Setup: [docs/online/SERVER.md](https://github.com/$REPO/blob/v$VERSION/docs/online/SERVER.md)
- **Supabase setup:** [CodeNote-supabase-$VERSION.zip]($BASE/CodeNote-supabase-$VERSION.zip). Setup: [docs/online/SUPABASE.md](https://github.com/$REPO/blob/v$VERSION/docs/online/SUPABASE.md)

**Check your download:** compare it with [SHA256SUMS.txt]($BASE/SHA256SUMS.txt) using \`sha256sum <file>\` (Linux), \`shasum -a 256 <file>\` (Mac) or \`certutil -hashfile <file> SHA256\` (Windows).
NOTES

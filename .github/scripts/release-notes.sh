#!/usr/bin/env bash
# Builds the GitHub Release text for one version.
# Usage: .github/scripts/release-notes.sh 1.4.0 > notes.md
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

cat <<NOTES
## CodeNote $VERSION

A notebook for code, notes and ideas. Local-only: your notes stay on your device.
$CHANGES

## Download

| Platform | File | How to install |
| --- | --- | --- |
| Android 7.0+ | [CodeNote-$VERSION-android.apk]($BASE/CodeNote-$VERSION-android.apk) | Open the file on your phone and tap Install. Updates install over the old version, and your notes stay. |
| Windows 10/11 | [CodeNote-$VERSION-windows-x64.zip]($BASE/CodeNote-$VERSION-windows-x64.zip) | Unzip, then run \`code_note.exe\`. If SmartScreen warns, click More info > Run anyway. |
| Ubuntu, Debian, Mint, Zorin | [CodeNote-$VERSION-linux-amd64.deb]($BASE/CodeNote-$VERSION-linux-amd64.deb) | \`sudo apt install ./CodeNote-$VERSION-linux-amd64.deb\`, then open CodeNote from the app menu. |
| Other Linux | [CodeNote-$VERSION-linux-x64.tar.gz]($BASE/CodeNote-$VERSION-linux-x64.tar.gz) | Extract, then run \`./code_note\` (needs GTK 3). |
| macOS 10.15+ | [CodeNote-$VERSION-macos.zip]($BASE/CodeNote-$VERSION-macos.zip) | Unzip and move to Applications. The first time, right-click the app > Open (it isn't notarized). |

**Check your download:** compare it with [SHA256SUMS.txt]($BASE/SHA256SUMS.txt) using \`sha256sum <file>\` (Linux), \`shasum -a 256 <file>\` (Mac) or \`certutil -hashfile <file> SHA256\` (Windows).

**Back up your notes:** Settings > Backup saves everything to one file you can restore anywhere.
NOTES

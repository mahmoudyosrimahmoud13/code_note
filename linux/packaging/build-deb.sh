#!/usr/bin/env bash
# Builds a .deb installer from a finished `flutter build linux --release`.
#
# Usage: linux/packaging/build-deb.sh <version>      e.g. 1.2.0
# Output: CodeNote-<version>-linux-amd64.deb in the project folder.
#
# What the package installs:
#   /opt/codenote/                     the app (binary, data, libs)
#   /usr/bin/codenote                  a command to start it from a terminal
#   /usr/share/applications/...        the app-menu entry
#   /usr/share/icons/hicolor/...       the icon (the CodeNote logo)
set -euo pipefail

VERSION="${1:?usage: build-deb.sh <version>}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUNDLE="$ROOT/build/linux/x64/release/bundle"
APP_ID="org.code.note.community"
PKG="$ROOT/build/deb/codenote_${VERSION}_amd64"

[ -x "$BUNDLE/code_note" ] || { echo "Run 'flutter build linux --release' first."; exit 1; }

rm -rf "$PKG"
mkdir -p "$PKG/DEBIAN" "$PKG/opt/codenote" "$PKG/usr/bin" \
         "$PKG/usr/share/applications" "$PKG/usr/share/icons/hicolor/512x512/apps" \
         "$PKG/usr/share/mime/packages"

# The app itself
cp -r "$BUNDLE/." "$PKG/opt/codenote/"
ln -s /opt/codenote/code_note "$PKG/usr/bin/codenote"

# Icon and app-menu entry. The .desktop file is named after the app ID so
# docks (GNOME, KDE) match the running window to the right icon.
cp "$ROOT/assets/logo/logo_rounded.png" "$PKG/usr/share/icons/hicolor/512x512/apps/$APP_ID.png"
cat > "$PKG/usr/share/applications/$APP_ID.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=CodeNote
GenericName=Code notebook
Comment=Notes for code, ideas and snippets, stored on this device
Exec=/opt/codenote/code_note %U
Icon=$APP_ID
Terminal=false
Categories=Development;Utility;TextEditor;
Keywords=notes;code;snippets;markdown;
MimeType=application/x-codenote;application/x-ipynb+json;x-scheme-handler/codenote;
StartupWMClass=code_note
DESKTOP

# .codenote files: a file type the system knows, so double-clicking one
# opens CodeNote (the system refreshes its file types after install).
cat > "$PKG/usr/share/mime/packages/$APP_ID.xml" <<MIME
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="application/x-codenote">
    <comment>CodeNote file</comment>
    <glob pattern="*.codenote"/>
    <icon name="$APP_ID"/>
  </mime-type>
</mime-info>
MIME

INSTALLED_KB=$(du -sk "$PKG" | cut -f1)
cat > "$PKG/DEBIAN/control" <<CONTROL
Package: codenote
Version: $VERSION
Section: devel
Priority: optional
Architecture: amd64
Depends: libgtk-3-0 | libgtk-3-0t64, libc6
Installed-Size: $INSTALLED_KB
Maintainer: Mahmoud Yosri <mahmoudyosrimahmoud13@users.noreply.github.com>
Homepage: https://github.com/mahmoudyosrimahmoud13/code_note
Description: CodeNote, a notebook for code, notes and ideas
 Mix text, code, markdown and images in one note, with syntax
 highlighting for 20+ languages. Community Edition: local-only,
 your notes never leave this device.
CONTROL

# Refresh the icon cache and app menu after install/remove (if the tools exist).
cat > "$PKG/DEBIAN/postinst" <<'SCRIPT'
#!/bin/sh
set -e
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q -t /usr/share/icons/hicolor || true
command -v update-desktop-database >/dev/null && update-desktop-database -q /usr/share/applications || true
SCRIPT
cp "$PKG/DEBIAN/postinst" "$PKG/DEBIAN/postrm"
chmod 755 "$PKG/DEBIAN/postinst" "$PKG/DEBIAN/postrm"

# Standard permissions, then build the package.
find "$PKG/opt" -type d -exec chmod 755 {} +
chmod 755 "$PKG/opt/codenote/code_note"
dpkg-deb --build --root-owner-group "$PKG" "$ROOT/CodeNote-$VERSION-linux-amd64.deb"
echo "Built CodeNote-$VERSION-linux-amd64.deb"

#!/bin/zsh
# GlassLink for Mac, ready to share: a universal (Apple silicon + Intel) app in a drag-to-install DMG.
#
#   scripts/package-macos.sh
#       Ad-hoc signed DMG. People open it once via System Settings > Privacy & Security >
#       Open Anyway (a "How to open" note is included in the DMG).
#
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" NOTARY_PROFILE=glasslink scripts/package-macos.sh
#       Signed and notarized DMG that opens without warnings (needs an Apple Developer account;
#       create the profile once with `xcrun notarytool store-credentials glasslink ...`).
#
# Output: dist/GlassLink-<version>.dmg
set -euo pipefail
ROOT="${0:A:h:h}"
VERSION=$(tr -d '[:space:]' < "$ROOT/VERSION")
DMG="$ROOT/dist/GlassLink-$VERSION.dmg"

UNIVERSAL=1 "$ROOT/macos/build.sh"

STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
ditto "$ROOT/macos/build.noindex/GlassLink.app" "$STAGING/GlassLink.app"
ln -s /Applications "$STAGING/Applications"
cp "$ROOT/LICENSE" "$STAGING/License (GPL-3.0).txt"

if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  cat > "$STAGING/How to open GlassLink.txt" <<'NOTE'
How to open GlassLink

1. Drag GlassLink into the Applications folder.
2. Open it. macOS says it can't verify the developer, because this copy isn't notarized by Apple.
   Click Done.
3. Open System Settings > Privacy & Security, scroll down, and click "Open Anyway" next to
   GlassLink. Confirm with your password.

You only need to do this once. When GlassLink asks to find devices on your local network,
click Allow: that's how it reaches your phone.

Next, install GlassLink for Android on your phone (the .apk on the same download page) and pair.

Requires macOS 26 Tahoe or later.
Source code and help: https://github.com/atikulmunna/GlassLink
NOTE
fi

mkdir -p "$ROOT/dist"
rm -f "$DMG"
hdiutil create -volname "GlassLink $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
  fi
fi
echo "Created ${DMG#$ROOT/} ($(du -h "$DMG" | cut -f1))"

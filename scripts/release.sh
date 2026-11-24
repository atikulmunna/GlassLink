#!/bin/zsh
# Builds everything people download, for the version in ./VERSION:
#   dist/GlassLink-<version>.dmg   macOS (see scripts/package-macos.sh)
#   dist/GlassLink-<version>.apk   Android (see scripts/package-android.sh)
#   dist/SHA256SUMS
#   dist/SHA256SUMS.sig            Ed25519 signature the Mac app checks before installing an update
#                                  (key: ~/.glasslink/update-signing.key, see tools/release-signing.swift)
#
#   scripts/release.sh             build only
#   scripts/release.sh --publish   build, then create the GitHub release v<version> with the
#                                  notes from CHANGELOG.md and the files attached
set -euo pipefail
ROOT="${0:A:h:h}"
cd "$ROOT"
VERSION=$(tr -d '[:space:]' < VERSION)

scripts/package-macos.sh
scripts/package-android.sh
(cd dist && shasum -a 256 "GlassLink-$VERSION.dmg" "GlassLink-$VERSION.apk" > SHA256SUMS)
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" swift tools/release-signing.swift sign dist/SHA256SUMS
echo "\nRelease files for $VERSION:"
ls -lh dist/GlassLink-$VERSION.* dist/SHA256SUMS dist/SHA256SUMS.sig | awk '{print "  " $NF " (" $5 ")"}'

if [[ "${1:-}" == "--publish" ]]; then
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "Commit your changes before publishing." >&2
    exit 1
  fi
  # This version's section of CHANGELOG.md becomes the release notes.
  NOTES=$(awk -v v="$VERSION" '$0 ~ "^## " v {found=1; next} found && /^## / {exit} found {print}' CHANGELOG.md)
  git push origin HEAD
  gh release create "v$VERSION" "dist/GlassLink-$VERSION.dmg" "dist/GlassLink-$VERSION.apk" dist/SHA256SUMS dist/SHA256SUMS.sig \
    --title "GlassLink $VERSION" --notes "$NOTES"
fi

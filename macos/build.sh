#!/bin/zsh
# Builds GlassLink.app with SwiftPM. Uses Xcode's toolchain when Xcode is installed (the macOS 27
# SDK's SwiftUI macros ship only with Xcode), otherwise the Command Line Tools.
#   ./build.sh            build into ./build.noindex/GlassLink.app (this Mac's architecture)
#   ./build.sh install    build, copy to /Applications (or ~/Applications) and relaunch
#   ./build.sh run        build and launch from the build folder
#
# Environment:
#   UNIVERSAL=1           build for Apple silicon and Intel
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)"
#                         sign for distribution (hardened runtime, timestamp); default is ad-hoc
set -euo pipefail
cd "${0:A:h}"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

APP_NAME=GlassLink
APP="build.noindex/$APP_NAME.app"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" Resources/Info.plist)

if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
else
  ARCH_FLAGS=(--arch "$(uname -m)")
fi

swift build -c release --product "$APP_NAME" "${ARCH_FLAGS[@]}"
BIN_DIR="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
  # Ad-hoc signature. The designated requirement names the bundle ID instead of the binary's
  # hash, so Local Network and notification permissions survive rebuilds.
  codesign --force --sign - --requirements "=designated => identifier \"$BUNDLE_ID\"" "$APP"
fi
codesign --verify --strict "$APP"
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/$APP_NAME"))"

case "${1:-}" in
  install)
    DEST=/Applications
    [[ -w "$DEST" ]] || DEST="$HOME/Applications"
    mkdir -p "$DEST"
    pkill -x "$APP_NAME" 2>/dev/null || true
    sleep 0.5
    rm -rf "$DEST/$APP_NAME.app"
    ditto "$APP" "$DEST/$APP_NAME.app"
    open "$DEST/$APP_NAME.app"
    echo "Installed to $DEST/$APP_NAME.app"
    ;;
  run)
    pkill -x "$APP_NAME" 2>/dev/null || true
    sleep 0.3
    open "$APP"
    ;;
esac

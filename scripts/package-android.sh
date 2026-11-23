#!/bin/zsh
# GlassLink for Android, ready to share: a release APK signed with the GlassLink release key.
#
# The key lives outside the repo, in ~/.glasslink/ (glasslink-release.jks + keystore.properties),
# or wherever GLASSLINK_KEYSTORE_PROPERTIES points. Back it up: every future update must be
# signed with the same key, or phones refuse to install it over the old version.
#
# Output: dist/GlassLink-<version>.apk
set -euo pipefail
ROOT="${0:A:h:h}"
VERSION=$(tr -d '[:space:]' < "$ROOT/VERSION")
APK="$ROOT/dist/GlassLink-$VERSION.apk"
PROPS="${GLASSLINK_KEYSTORE_PROPERTIES:-$HOME/.glasslink/keystore.properties}"

if [[ ! -f "$PROPS" ]]; then
  echo "No release key found at $PROPS." >&2
  echo "Create one (once) with keytool and describe it in that file; see the README, 'Releasing'." >&2
  exit 1
fi

# Toolchain: Homebrew's JDK 21 and the standard SDK location, unless already set.
if [[ -z "${JAVA_HOME:-}" && -d /opt/homebrew/opt/openjdk@21 ]]; then
  export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
fi
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
[[ -f "$ROOT/android/local.properties" ]] || echo "sdk.dir=$ANDROID_HOME" > "$ROOT/android/local.properties"

(cd "$ROOT/android" && ./gradlew --quiet assembleRelease)

BUILT="$ROOT/android/build/outputs/apk/release/kdeconnect-android-release.apk"
APKSIGNER=$(ls -d "$ANDROID_HOME"/build-tools/*/ | sort -V | tail -1)apksigner
"$APKSIGNER" verify "$BUILT"
mkdir -p "$ROOT/dist"
cp "$BUILT" "$APK"
echo "Created ${APK#$ROOT/} ($(du -h "$APK" | cut -f1))"

#!/bin/zsh
# Runs the protocol tests (loopback handshake, TLS, payloads, certificate pinning).
set -euo pipefail
cd "${0:A:h}"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
# The Command Line Tools keep the Swift Testing macros in a folder SwiftPM doesn't search.
PLUGINS="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}/usr/lib/swift/host/plugins/testing"
if [[ "${DEVELOPER_DIR:-}" != *Xcode* && -d "$PLUGINS" ]]; then
  exec swift test -Xswiftc -plugin-path -Xswiftc "$PLUGINS" "$@"
fi
exec swift test "$@"

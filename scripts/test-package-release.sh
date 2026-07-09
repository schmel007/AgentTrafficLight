#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

APP="$TMP/Test App.app"
mkdir -p "$APP/Contents/MacOS"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$APP/Contents/MacOS/TestApp"
chmod 755 "$APP/Contents/MacOS/TestApp"
ZIP="$TMP/output/AgentSignals.zip"

sh "$ROOT_DIR/scripts/package-release.sh" "$APP" "$ZIP" >/dev/null
[ -f "$ZIP" ] || fail "package zip was not created"

UNPACKED="$TMP/unpacked"
ditto -x -k "$ZIP" "$UNPACKED"
PACKAGE="$UNPACKED/Agent Signals"
[ -d "$PACKAGE/Agent Signals.app" ] || fail "app is missing from package"
[ -x "$PACKAGE/agent-status.sh" ] || fail "hook is missing or not executable"
[ -x "$PACKAGE/install-hooks.sh" ] || fail "installer is missing or not executable"
[ -f "$PACKAGE/install-hooks.jq" ] || fail "installer filter is missing"
[ -f "$PACKAGE/remove-hooks.jq" ] || fail "uninstaller filter is missing"
[ -f "$PACKAGE/README.md" ] || fail "installation guide is missing"
[ -f "$PACKAGE/LICENSE" ] || fail "license is missing"

HOME="$TMP/package-home" sh "$PACKAGE/install-hooks.sh" >/dev/null
HOME="$TMP/package-home" sh "$PACKAGE/install-hooks.sh" --check >/dev/null

echo "ALL PASS"

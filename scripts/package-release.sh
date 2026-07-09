#!/bin/sh
# Builds the public ZIP without modifying the signed app bundle.
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
APP_PATH="${1:-}"
OUTPUT_ZIP="${2:-}"

fail() {
  echo "Agent Signals packager: $1" >&2
  exit 1
}

[ -n "$APP_PATH" ] && [ -n "$OUTPUT_ZIP" ] || fail "usage: package-release.sh <app-path> <output-zip>"
[ -d "$APP_PATH" ] || fail "app bundle not found: $APP_PATH"
[ -f "$ROOT_DIR/hooks/agent-status.sh" ] || fail "hook script is missing"
[ -f "$ROOT_DIR/scripts/install-hooks.sh" ] || fail "installer is missing"
[ -f "$ROOT_DIR/docs/INSTALL.md" ] || fail "installation guide is missing"

OUTPUT_DIR="$(dirname "$OUTPUT_ZIP")"
mkdir -p "$OUTPUT_DIR"
[ ! -L "$OUTPUT_DIR" ] || fail "output directory must not be a symbolic link"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/agent-signals-package.XXXXXX")"
TEMP_ZIP="$(mktemp "$OUTPUT_DIR/.AgentSignals.XXXXXX")"
rm -f "$TEMP_ZIP"
trap 'rm -rf "$STAGE"; rm -f "$TEMP_ZIP"' EXIT HUP INT TERM

PACKAGE_DIR="$STAGE/Agent Signals"
mkdir -p "$PACKAGE_DIR"
ditto "$APP_PATH" "$PACKAGE_DIR/Agent Signals.app"
install -m 755 "$ROOT_DIR/hooks/agent-status.sh" "$PACKAGE_DIR/agent-status.sh"
install -m 755 "$ROOT_DIR/scripts/install-hooks.sh" "$PACKAGE_DIR/install-hooks.sh"
install -m 644 "$ROOT_DIR/scripts/install-hooks.jq" "$PACKAGE_DIR/install-hooks.jq"
install -m 644 "$ROOT_DIR/scripts/remove-hooks.jq" "$PACKAGE_DIR/remove-hooks.jq"
install -m 644 "$ROOT_DIR/docs/INSTALL.md" "$PACKAGE_DIR/README.md"
install -m 644 "$ROOT_DIR/LICENSE" "$PACKAGE_DIR/LICENSE"

ditto -c -k --keepParent "$PACKAGE_DIR" "$TEMP_ZIP"
mv -f "$TEMP_ZIP" "$OUTPUT_ZIP"
trap - EXIT HUP INT TERM
rm -rf "$STAGE"

echo "Release package: $OUTPUT_ZIP"

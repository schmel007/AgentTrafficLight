#!/bin/sh
# Runs the complete local and CI verification gate.
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
PROJECT="$ROOT_DIR/AgentTrafficLight/AgentTrafficLight.xcodeproj"
SCHEME="AgentTrafficLight"
DERIVED_DATA="$(mktemp -d "${TMPDIR:-/tmp}/agent-signals-derived-data.XXXXXX")"
trap 'rm -rf "$DERIVED_DATA"' EXIT HUP INT TERM

command -v jq >/dev/null 2>&1 || { echo "verify: jq is required" >&2; exit 1; }
command -v xcodebuild >/dev/null 2>&1 || { echo "verify: xcodebuild is required" >&2; exit 1; }

cd "$ROOT_DIR"

sh -n hooks/agent-status.sh hooks/test_agent-status.sh \
  scripts/install-hooks.sh scripts/test-install-hooks.sh \
  scripts/package-release.sh scripts/test-package-release.sh \
  scripts/release.sh scripts/verify.sh
plutil -lint AgentTrafficLight/AgentTrafficLight/AgentTrafficLight.entitlements \
  AgentTrafficLight/AgentTrafficLight.xcodeproj/project.pbxproj >/dev/null
printf '{}\n' | jq \
  --arg working working --arg waiting waiting --arg completed 'done' --arg end end --arg agent claude \
  -f scripts/install-hooks.jq >/dev/null
printf '{}\n' | jq -f scripts/remove-hooks.jq >/dev/null

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck hooks/agent-status.sh hooks/test_agent-status.sh \
    scripts/install-hooks.sh scripts/test-install-hooks.sh \
    scripts/package-release.sh scripts/test-package-release.sh \
    scripts/release.sh scripts/verify.sh
fi

sh hooks/test_agent-status.sh
sh scripts/test-install-hooks.sh
sh scripts/test-package-release.sh

xcodebuild test \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA/tests" \
  -only-testing:AgentTrafficLightTests \
  -only-testing:AgentTrafficLightUITests

xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA/release" \
  CODE_SIGNING_ALLOWED=NO

APP="$DERIVED_DATA/release/Build/Products/Release/AgentTrafficLight.app"
BIN="$APP/Contents/MacOS/AgentTrafficLight"
[ -x "$BIN" ] || { echo "verify: Release binary is missing" >&2; exit 1; }
[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")" = "13.0" ] \
  || { echo "verify: minimum macOS version is not 13.0" >&2; exit 1; }
ARCHS="$(lipo -archs "$BIN")"
case " $ARCHS " in *' arm64 '*) ;; *) echo "verify: arm64 slice is missing" >&2; exit 1 ;; esac
case " $ARCHS " in *' x86_64 '*) ;; *) echo "verify: x86_64 slice is missing" >&2; exit 1 ;; esac

PUBLIC_ZIP="$DERIVED_DATA/public/AgentSignals.zip"
PUBLIC_UNPACKED="$DERIVED_DATA/public-unpacked"
sh scripts/package-release.sh "$APP" "$PUBLIC_ZIP" >/dev/null
ditto -x -k "$PUBLIC_ZIP" "$PUBLIC_UNPACKED"
PACKAGED_APP="$PUBLIC_UNPACKED/Agent Signals/Agent Signals.app"
PACKAGED_BIN="$PACKAGED_APP/Contents/MacOS/AgentTrafficLight"
[ -x "$PUBLIC_UNPACKED/Agent Signals/install-hooks.sh" ] \
  || { echo "verify: installer is missing from the real Release package" >&2; exit 1; }
cmp -s "$BIN" "$PACKAGED_BIN" \
  || { echo "verify: packaged Release binary differs from the verified build" >&2; exit 1; }
[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PACKAGED_APP/Contents/Info.plist")" = "13.0" ] \
  || { echo "verify: packaged app minimum macOS version is not 13.0" >&2; exit 1; }
[ "$(lipo -archs "$PACKAGED_BIN")" = "$ARCHS" ] \
  || { echo "verify: packaged app architectures differ from the verified build" >&2; exit 1; }

git diff --check
echo "ALL VERIFICATION PASSED"

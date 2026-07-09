#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
PROJECT="$ROOT_DIR/AgentTrafficLight/AgentTrafficLight.xcodeproj"
SCHEME="AgentTrafficLight"
CONFIGURATION="Release"
RAW_PRODUCT_NAME="AgentTrafficLight"
APP_NAME="Agent Signals"
TEAM_ID="${TEAM_ID:-88HMCU8P46}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AgentSignalsNotary}"
BUILD_ROOT="$ROOT_DIR/build"
DIST_DIR="$ROOT_DIR/dist"
FINAL_ZIP="$DIST_DIR/AgentSignals.zip"

usage() {
  cat <<'USAGE'
Usage:
  scripts/release.sh --preflight
  scripts/release.sh

Environment:
  NOTARY_PROFILE   Keychain profile for xcrun notarytool. Default: AgentSignalsNotary
  TEAM_ID          Apple Developer Team ID. Default: 88HMCU8P46

Before the first release, configure notarization credentials:
  xcrun notarytool store-credentials AgentSignalsNotary \
    --apple-id "APPLE_ID_EMAIL" \
    --team-id "TEAM_ID" \
    --password "APP_SPECIFIC_PASSWORD"
USAGE
}

fail() {
  echo "Release blocked: $1" >&2
  exit 1
}

has_developer_id_certificate() {
  security find-identity -v -p codesigning 2>/dev/null | grep -q '"Developer ID Application:'
}

preflight() {
  missing=0

  for command in xcodebuild git jq ditto codesign spctl; do
    if ! command -v "$command" >/dev/null 2>&1; then
      echo "Missing $command." >&2
      missing=1
    fi
  done

  if ! xcrun -f notarytool >/dev/null 2>&1; then
    echo "Missing xcrun notarytool." >&2
    missing=1
  fi

  if ! xcrun -f stapler >/dev/null 2>&1; then
    echo "Missing xcrun stapler." >&2
    missing=1
  fi

  if ! has_developer_id_certificate; then
    echo "Missing Developer ID Application certificate in the login keychain." >&2
    missing=1
  fi

  if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "Missing or invalid notarytool keychain profile: $NOTARY_PROFILE" >&2
    missing=1
  fi

  [ "$missing" -eq 0 ] || return 1
  echo "Preflight OK."
}

marketing_version() {
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -showBuildSettings 2>/dev/null \
    | awk '$1 == "MARKETING_VERSION" { print $3; exit }'
}

require_release_source() {
  [ -z "$(git -C "$ROOT_DIR" status --porcelain)" ] || fail "working tree is not clean"
  version="$(marketing_version)"
  [ -n "$version" ] || fail "MARKETING_VERSION could not be read"
  tag="$(git -C "$ROOT_DIR" describe --tags --exact-match HEAD 2>/dev/null || true)"
  [ "$tag" = "v$version" ] || fail "HEAD must be tagged v$version"
  grep -F "## $version -" "$ROOT_DIR/CHANGELOG.md" >/dev/null \
    || fail "CHANGELOG.md has no release entry for $version"
}

case "${1:-}" in
  --help|-h)
    usage
    exit 0
    ;;
  --preflight)
    preflight
    exit $?
    ;;
  '') ;;
  *)
    usage >&2
    exit 2
    ;;
esac

preflight
require_release_source
sh "$ROOT_DIR/scripts/verify.sh"

[ ! -L "$BUILD_ROOT" ] || fail "$BUILD_ROOT must not be a symbolic link"
[ ! -L "$DIST_DIR" ] || fail "$DIST_DIR must not be a symbolic link"
mkdir -p "$BUILD_ROOT" "$DIST_DIR"

BUILD_DIR="$(mktemp -d "$BUILD_ROOT/release.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT HUP INT TERM
ARCHIVE_PATH="$BUILD_DIR/AgentSignals.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_OPTIONS="$BUILD_DIR/exportOptions.plist"
NOTARY_ZIP="$BUILD_DIR/AgentSignals-notary.zip"

cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>destination</key>
	<string>export</string>
	<key>method</key>
	<string>developer-id</string>
	<key>signingCertificate</key>
	<string>Developer ID Application</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>stripSwiftSymbols</key>
	<true/>
	<key>teamID</key>
	<string>$TEAM_ID</string>
</dict>
</plist>
PLIST

xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH"

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS"

if [ -d "$EXPORT_DIR/$RAW_PRODUCT_NAME.app" ]; then
  mv "$EXPORT_DIR/$RAW_PRODUCT_NAME.app" "$EXPORT_DIR/$APP_NAME.app"
fi

APP_PATH="$EXPORT_DIR/$APP_NAME.app"
[ -d "$APP_PATH" ] || fail "exported app not found: $APP_PATH"

codesign --verify --deep --strict "$APP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$NOTARY_ZIP"
xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
spctl -a -vvv -t exec "$APP_PATH"

sh "$ROOT_DIR/scripts/package-release.sh" "$APP_PATH" "$FINAL_ZIP"
PACKAGE_CHECK="$BUILD_DIR/package-check"
ditto -x -k "$FINAL_ZIP" "$PACKAGE_CHECK"
PACKAGED_APP="$PACKAGE_CHECK/Agent Signals/Agent Signals.app"
codesign --verify --deep --strict "$PACKAGED_APP"
xcrun stapler validate "$PACKAGED_APP"
spctl -a -vvv -t exec "$PACKAGED_APP"

echo "Release archive: $FINAL_ZIP"

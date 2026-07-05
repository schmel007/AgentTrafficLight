#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT_DIR/AgentTrafficLight/AgentTrafficLight.xcodeproj"
SCHEME="AgentTrafficLight"
CONFIGURATION="Release"
RAW_PRODUCT_NAME="AgentTrafficLight"
APP_NAME="Agent Signals"
TEAM_ID="${TEAM_ID:-88HMCU8P46}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AgentSignalsNotary}"

BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build/release}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
ARCHIVE_PATH="$BUILD_DIR/AgentSignals.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_OPTIONS="$BUILD_DIR/exportOptions.plist"
NOTARY_ZIP="$BUILD_DIR/AgentSignals-notary.zip"
FINAL_ZIP="$DIST_DIR/AgentSignals.zip"

usage() {
  cat <<USAGE
Usage:
  scripts/release.sh --preflight
  scripts/release.sh

Environment:
  NOTARY_PROFILE   Keychain profile for xcrun notarytool. Default: AgentSignalsNotary
  TEAM_ID          Apple Developer Team ID. Default: 88HMCU8P46
  BUILD_DIR        Temporary build directory. Default: ./build/release
  DIST_DIR         Output directory. Default: ./dist

Before the first release, configure notarization credentials:
  xcrun notarytool store-credentials AgentSignalsNotary \\
    --apple-id "APPLE_ID_EMAIL" \\
    --team-id "$TEAM_ID" \\
    --password "APP_SPECIFIC_PASSWORD"
USAGE
}

has_developer_id_certificate() {
  security find-identity -v -p codesigning 2>/dev/null | grep -q '"Developer ID Application:'
}

preflight() {
  missing=0

  if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "Missing xcodebuild." >&2
    missing=1
  fi

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
    echo "Install it from Xcode Accounts or Apple Developer Certificates." >&2
    missing=1
  fi

  if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "Missing or invalid notarytool keychain profile: $NOTARY_PROFILE" >&2
    echo "Create it with:" >&2
    echo "  xcrun notarytool store-credentials $NOTARY_PROFILE \\" >&2
    echo "    --apple-id \"APPLE_ID_EMAIL\" \\" >&2
    echo "    --team-id \"$TEAM_ID\" \\" >&2
    echo "    --password \"APP_SPECIFIC_PASSWORD\"" >&2
    missing=1
  fi

  if [ "$missing" -ne 0 ]; then
    return 1
  fi

  echo "Preflight OK."
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
  "")
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

preflight

rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

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
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH"

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS"

if [ -d "$EXPORT_DIR/$RAW_PRODUCT_NAME.app" ]; then
  rm -rf "$EXPORT_DIR/$APP_NAME.app"
  mv "$EXPORT_DIR/$RAW_PRODUCT_NAME.app" "$EXPORT_DIR/$APP_NAME.app"
fi

APP_PATH="$EXPORT_DIR/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
  echo "Exported app not found: $APP_PATH" >&2
  exit 1
fi

codesign --verify --deep --strict "$APP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$NOTARY_ZIP"

xcrun notarytool submit "$NOTARY_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
spctl -a -vvv -t exec "$APP_PATH"

ditto -c -k --keepParent "$APP_PATH" "$FINAL_ZIP"

echo "Release archive: $FINAL_ZIP"

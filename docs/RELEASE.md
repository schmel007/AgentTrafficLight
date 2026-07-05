# Release

Agent Signals is distributed as a Developer ID notarized zip archive.

## Prerequisites

- Apple Developer Program membership
- `Developer ID Application` certificate installed in Keychain
- Xcode command-line tools
- notarytool credentials stored in Keychain

Store notarytool credentials once:

```bash
xcrun notarytool store-credentials AgentSignalsNotary \
  --apple-id "APPLE_ID_EMAIL" \
  --team-id "TEAM_ID" \
  --password "APP_SPECIFIC_PASSWORD"
```

Use an app-specific password from Apple ID settings, not the Apple ID account password.

## Preflight

```bash
scripts/release.sh --preflight
```

The preflight checks for:

- `xcodebuild`
- `notarytool`
- `stapler`
- a `Developer ID Application` certificate
- a valid notarytool Keychain profile

## Build And Notarize

```bash
scripts/release.sh
```

The script:

1. Archives the macOS app.
2. Exports it with Developer ID signing.
3. Renames the exported bundle to `Agent Signals.app`.
4. Verifies the code signature.
5. Uploads the zip to Apple notarization.
6. Staples the notarization ticket.
7. Validates with `stapler` and `spctl`.
8. Writes `dist/AgentSignals.zip`.

## Configuration

Defaults:

```bash
TEAM_ID=88HMCU8P46
NOTARY_PROFILE=AgentSignalsNotary
BUILD_DIR=./build/release
DIST_DIR=./dist
```

Override when needed:

```bash
TEAM_ID=YOUR_TEAM_ID NOTARY_PROFILE=YourProfile scripts/release.sh
```

## Manual Verification

```bash
TMPDIR_RELEASE="/tmp/agent-signals-release-check"
rm -rf "$TMPDIR_RELEASE"
mkdir -p "$TMPDIR_RELEASE"
ditto -x -k dist/AgentSignals.zip "$TMPDIR_RELEASE"
APP="$TMPDIR_RELEASE/Agent Signals.app"
codesign --verify --deep --strict "$APP"
xcrun stapler validate "$APP"
spctl -a -vvv -t exec "$APP"
```

Expected Gatekeeper result:

```text
accepted
source=Notarized Developer ID
```

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

The full release additionally requires:

- a clean working tree with no untracked files;
- `HEAD` tagged exactly as `v<MARKETING_VERSION>`;
- a matching dated entry in `CHANGELOG.md`;
- a successful `scripts/verify.sh` run.

## Build And Notarize

```bash
scripts/release.sh
```

The script:

1. Runs the complete verification gate.
2. Creates a unique temporary build directory under `build/`.
3. Archives and exports the macOS app with Developer ID signing.
4. Verifies the code signature.
5. Uploads the app-only archive to Apple notarization.
6. Staples and validates the notarization ticket.
7. Creates a public package containing the app, hook, installer, install guide, and license.
8. Extracts that final package and validates its app again with `codesign`, `stapler`, and
   `spctl`.
9. Atomically writes `dist/AgentSignals.zip` without deleting the rest of `dist/`.

## Configuration

Configuration:

```bash
TEAM_ID=88HMCU8P46
NOTARY_PROFILE=AgentSignalsNotary
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
APP="$TMPDIR_RELEASE/Agent Signals/Agent Signals.app"
codesign --verify --deep --strict "$APP"
xcrun stapler validate "$APP"
spctl -a -vvv -t exec "$APP"
```

Expected Gatekeeper result:

```text
accepted
source=Notarized Developer ID
```

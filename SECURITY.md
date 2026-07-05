# Security

## Supported Versions

Security fixes are handled on the `main` branch.

## Reporting A Vulnerability

Use GitHub private vulnerability reporting if it is enabled for this repository. If it is
not available, open an issue with a minimal reproducer and avoid posting sensitive local
paths, credentials, or private project data.

## Security Model

Agent Signals is a local macOS menu bar app. It:

- reads status files from `~/.claude/agent-traffic/`;
- executes `/usr/bin/osascript` to inspect and focus iTerm tabs;
- does not send telemetry.

The app is intentionally not sandboxed because it needs access to local hook output and
iTerm Automation. Public builds should be signed with Developer ID, notarized, stapled,
and verified with Gatekeeper.

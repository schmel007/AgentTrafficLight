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

Status filenames never interpolate untrusted session ids containing path separators. Both
producer and consumer reject a symbolic-link status directory. The consumer also ignores
symbolic-link records and deletes only regular JSON files it enumerated directly inside the
status directory. Hook output is private to the current user (`0700` directory, `0600`
records).

The public installer merges only Agent Signals handlers into existing Claude Code and Codex
JSON configuration. It preserves unrelated hooks and writes a backup before replacing an
existing configuration file. Codex users must review and trust new hook definitions through
`/hooks` before Codex runs them.

# Changelog

## 1.1.0 - 2026-07-05

- Fixed: nested Codex runs spawned inside a Claude Code session (review helpers etc.)
  no longer steal the tab row and flip its agent icon.
- Changed: menu labels now prefer the live iTerm session title over the static tab
  title, so labels always match what the tab shows, including renames.
- Fixed: the hook test suite is hermetic when run from an iTerm or Claude Code
  environment.

## 1.0.0 - 2026-07-05

- Added the Developer ID notarized release pipeline.
- Added public documentation for architecture, release, privacy, and security.
- Added Apple Events entitlement and usage description for iTerm Automation.
- Polished app branding as Agent Signals.
- Changed menu labels to prefer iTerm tab titles over session names.

## Notes

The internal Xcode target and bundle identifier currently remain `AgentTrafficLight` for
continuity with local permissions, signing, and repository history.

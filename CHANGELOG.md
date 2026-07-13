# Changelog

## 1.1.3 - 2026-07-13

- Easier setup: the download now includes the app, a safe hook installer, and a quick-start
  guide, so Agent Signals works without a source checkout.
- More dependable signals: Codex approval waits and post-tool activity are reflected promptly,
  while hardened session handling keeps stale or unrelated activity out of the menu.
- Broader compatibility: the universal app now supports macOS 13 and later, with a stricter
  release gate for a safer, more predictable install.

## 1.1.2 - 2026-07-08

- Fixed: finished (🟢) and waiting (🔴) sessions no longer linger indefinitely when their
  recorded process id is reused or belongs to a shared, long-lived Claude Code process
  (such as a background spare) that outlives the session. Any session without hook
  activity for more than one hour is now aged out, matching the existing behavior for
  working (🟡) sessions.

## 1.1.1 - 2026-07-05

- Fixed: manually set iTerm tab titles win again. 1.1.0 always used the live session
  name, which replaced meaningful manual titles with defaults like `user (codex)` for
  finished Codex sessions. Tabs without a manual title still follow the live session
  name.

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

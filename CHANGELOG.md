# Changelog

## Unreleased

- Fixed: the public release package now includes an idempotent Claude Code and Codex hook
  installer, the producer script, a quick-start guide, and the license.
- Fixed: Codex permission and post-tool events now provide waiting-state parity and refresh
  working-state liveness.
- Fixed: non-iTerm Claude Code sessions no longer pollute the iTerm-only counter.
- Fixed: same-second iTerm snapshot races no longer delete newly created session records.
- Security: session ids cannot escape the status directory, symlink records are ignored,
  and hook output uses user-only permissions.
- Release: macOS 13 is now the minimum deployment target; builds are macOS-only and universal
  for Apple silicon and Intel.
- Release: destructive output-directory overrides were removed; releases now require a clean,
  exactly tagged source tree and a complete automated verification gate.

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

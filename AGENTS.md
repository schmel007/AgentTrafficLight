# Contributor & Agent Guide

**This repository is public.** Everything committed here — code, comments, commit
messages, images — is visible to everyone. Before every commit check that it contains:

- **No secrets:** credentials, tokens, API keys, notarization passwords. Notarytool
  credentials live only in the macOS Keychain (see [docs/RELEASE.md](docs/RELEASE.md)).
- **No personal data:** real email addresses (git is configured to a GitHub noreply
  address), local absolute paths, or screenshots with private content in the
  background — crop or blur before adding anything to `docs/assets/`.
- **No session artifacts:** `.claude/`, `.agent/`, scratch files, logs. They are
  gitignored; keep it that way.
- **English only** in code comments, commit messages, and docs. The Cyrillic strings
  in `AggregatorTests` are intentional non-ASCII fixtures — keep them.

## Commits

- Style: `type: subject` (`feat:`, `fix:`, `docs:`, `chore:`), one topic per commit.
- No AI co-author trailers.
- Stage explicit paths; avoid blanket `git add -A` — it silently commits unrelated
  working-tree changes, including accidental deletions.

## Build & test

```bash
scripts/verify.sh
```

The gate covers hook, installer, packaging, unit, UI, universal Release, deployment-target,
shell syntax, plist, and optional ShellCheck validation. Hook tests explicitly control
`ITERM_SESSION_ID`, `CLAUDECODE`, and `CLAUDE_CODE_ENTRYPOINT`, so they are hermetic in shells
spawned by coding agents.

## Behavioral invariants — do not "fix" without reading docs/ARCHITECTURE.md

- Menu row labels: the manual iTerm tab title (`title of t`) wins; the live session
  name (`name of s`) is only a fallback for tabs without a manual title. Version
  1.1.0 inverted this preference and was reverted in 1.1.1.
- Liveness checks and status-file cleanup never depend on iTerm queries; osascript
  is used only for cosmetic names and tab focus.
- Codex events fired from inside a Claude Code session (env `CLAUDECODE` /
  `CLAUDE_CODE_ENTRYPOINT`) are ignored by `hooks/agent-status.sh` — nested helper
  runs must not steal the tab row from the visible session.
- Codex Desktop events (no `ITERM_SESSION_ID`) never reach the counter.

## Release

`scripts/release.sh` — Developer ID signing, notarization, Gatekeeper validation;
see [docs/RELEASE.md](docs/RELEASE.md). The public app name is "Agent Signals"; the
internal target, scheme, and bundle identifier remain `AgentTrafficLight`.

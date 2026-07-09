# Architecture

Agent Signals has two parts connected by local JSON files.

## Producer

[hooks/agent-status.sh](../hooks/agent-status.sh) receives agent hook events and writes
one status file per session to:

```text
~/.claude/agent-traffic/<session_id>.json
```

The script records:

- `session_id`
- `state`
- `pid`
- `ts`
- `agent`
- `cwd`
- `iterm`

If a payload does not contain a session id, the script falls back to `AGENT_TRAFFIC_SID`
and then `pid-<pid>`. Filename-safe ids remain readable; unexpected ids are hashed before
being used as filenames. Files are written atomically through a unique same-directory
temporary file and `mv`. The directory mode is `0700` and record mode is `0600`.
The producer rejects a status directory that is a symbolic link.

Events from either agent without `ITERM_SESSION_ID` are treated as desktop or non-iTerm
context and are removed instead of counted.

## Consumer

The SwiftUI menu bar app polls the status directory every two seconds.

Core logic lives in [Aggregator.swift](../AgentTrafficLight/AgentTrafficLight/Aggregator.swift):

- filter records that are not visible terminal sessions;
- deduplicate records by iTerm GUID;
- compute counts for 🔴, 🟡, 🟢, and ⚠️;
- mark stale or dead records for deletion;
- generate the internal diagnostics report.

[StatusStore.swift](../AgentTrafficLight/AgentTrafficLight/StatusStore.swift) handles file IO,
periodic refreshes, iTerm AppleScript calls, tab-title lookup, and tab focusing.
It rejects a symbolic-link status directory, reads only regular direct-child JSON files, and
deletes the exact files discovered during the same refresh. JSON contents can never select an
arbitrary deletion path.

## State Semantics

| State | Menu signal | Rule |
|-------|-------------|------|
| `waiting` | 🔴 | Process is alive and waiting for input or approval |
| `working` | 🟡 | Process is alive and recent |
| `done` | 🟢 | Process is alive and finished |
| dead `working` | ⚠️ | The process died before sending `Stop` |

Dead `done` and `waiting` records are deleted. Records older than one hour are deleted
regardless of state: a stale timestamp means the `pid` is no longer a trustworthy liveness
proxy — the process may have exited and had its id reused, or the hook recorded a shared,
long-lived Claude Code process (e.g. a background spare) that outlives the session.

## iTerm Integration

The app uses AppleScript through `/usr/bin/osascript` to:

- list open iTerm sessions and their GUIDs;
- resolve row labels (manual tab title first, live session name as fallback);
- focus the clicked tab.

The iTerm query is throttled and guarded by a timeout. If Automation is denied or iTerm
does not respond, the app falls back to project directory names and avoids destructive
cleanup based on unavailable iTerm data.

Hook timestamps have one-second precision. Records from the same second in which an iTerm
snapshot started are retained until the next snapshot, preventing a newly created session
from being mistaken for a closed tab.

## Distribution Posture

App Sandbox is disabled by design. The app reads `~/.claude/agent-traffic/` and sends
Apple Events to iTerm. Public distribution uses Developer ID notarization, not the Mac
App Store.

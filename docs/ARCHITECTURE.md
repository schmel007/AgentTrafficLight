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
and then `pid-<pid>`. Files are written atomically through a temporary file and `mv`.

Codex events without `ITERM_SESSION_ID` are treated as desktop or non-iTerm context and
are removed instead of counted.

## Consumer

The SwiftUI menu bar app polls the status directory every two seconds.

Core logic lives in [Aggregator.swift](../AgentTrafficLight/AgentTrafficLight/Aggregator.swift):

- filter records that are not visible terminal sessions;
- deduplicate records by iTerm GUID;
- compute counts for 🔴, 🟡, 🟢, and ⚠️;
- mark stale or dead records for deletion;
- generate the internal diagnostics report.

[StatusStore.swift](../AgentTrafficLight/AgentTrafficLight/StatusStore.swift) handles file IO,
periodic refreshes, iTerm AppleScript calls, tab-name lookup, and tab focusing.

## State Semantics

| State | Menu signal | Rule |
|-------|-------------|------|
| `waiting` | 🔴 | Process is alive and waiting for input or approval |
| `working` | 🟡 | Process is alive and recent |
| `done` | 🟢 | Process is alive and finished |
| dead `working` | ⚠️ | The process died before sending `Stop` |

Dead `done` and `waiting` records are deleted. `working` records older than one hour are
deleted to reduce stale process-id reuse.

## iTerm Integration

The app uses AppleScript through `/usr/bin/osascript` to:

- list open iTerm sessions and their GUIDs;
- resolve tab names;
- focus the clicked tab.

The iTerm query is throttled and guarded by a timeout. If Automation is denied or iTerm
does not respond, the app falls back to project directory names and avoids destructive
cleanup based on unavailable iTerm data.

## Distribution Posture

App Sandbox is disabled by design. The app reads `~/.claude/agent-traffic/` and sends
Apple Events to iTerm. Public distribution uses Developer ID notarization, not the Mac
App Store.

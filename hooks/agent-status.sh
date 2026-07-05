#!/bin/sh
# Writes an agent session status (Claude Code / Codex) to a file for Agent Signals.
# Usage: agent-status.sh <working|waiting|done|end> [claude|codex]
set -eu

DIR="${AGENT_TRAFFIC_DIR:-$HOME/.claude/agent-traffic}"
STATE="${1:-}"
[ -z "$STATE" ] && exit 0
KIND="${2:-claude}"
mkdir -p "$DIR"

PAYLOAD="$(cat 2>/dev/null || true)"

# Agent process pid (grandparent of the hook script) — a session liveness proxy
PID="${AGENT_TRAFFIC_PID:-$(ps -o ppid= -p "$PPID" 2>/dev/null | tr -d ' ')}"
[ -z "$PID" ] && PID=0

# session_id: from payload, else env, else pid-<pid> (unique even without a session_id, e.g. Codex)
SID="$(printf '%s' "$PAYLOAD" | jq -r '.session_id // .sessionId // empty' 2>/dev/null || true)"
[ -z "$SID" ] && SID="${AGENT_TRAFFIC_SID:-}"
[ -z "$SID" ] && SID="pid-$PID"

FILE="$DIR/$SID.json"

if [ "$STATE" = "end" ]; then
  rm -f "$FILE"
  exit 0
fi

ITERM="${ITERM_SESSION_ID:-}"

# The indicator counts iTerm tabs. Codex Desktop also executes ~/.codex/hooks.json,
# but it has no ITERM_SESSION_ID; such events must not reach the counter.
if [ "$KIND" = "codex" ] && [ -z "$ITERM" ]; then
  rm -f "$FILE"
  exit 0
fi

CWD="$(printf '%s' "$PAYLOAD" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -z "$CWD" ] && CWD="$PWD"
TS="$(date +%s)"

# Atomic write: temp + mv (rename) so the consumer never reads a half-written file
TMP="$FILE.tmp.$$"
jq -n \
  --arg sid "$SID" \
  --arg state "$STATE" \
  --argjson pid "${PID:-0}" \
  --argjson ts "$TS" \
  --arg agent "$KIND" \
  --arg cwd "$CWD" \
  --arg iterm "$ITERM" \
  '{session_id:$sid, state:$state, pid:$pid, ts:$ts, agent:$agent, cwd:$cwd, iterm:$iterm}' > "$TMP"
mv -f "$TMP" "$FILE"

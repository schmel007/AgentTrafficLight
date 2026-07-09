#!/bin/sh
# Writes an agent session status (Claude Code / Codex) to a file for Agent Signals.
# Usage: agent-status.sh <working|waiting|done|end> [claude|codex]
set -eu

umask 077

DIR="${AGENT_TRAFFIC_DIR:-$HOME/.claude/agent-traffic}"
STATE="${1:-}"
KIND="${2:-claude}"

case "$STATE" in
  working|waiting|done|end) ;;
  *)
    echo "Invalid Agent Signals state: ${STATE:-<empty>}" >&2
    exit 1
    ;;
esac

case "$KIND" in
  claude|codex) ;;
  *)
    echo "Invalid Agent Signals agent kind: $KIND" >&2
    exit 1
    ;;
esac

if ! command -v jq >/dev/null 2>&1; then
  echo "Agent Signals hook requires jq." >&2
  exit 1
fi

# Nested Codex runs spawned inside a Claude Code session inherit the tab's
# ITERM_SESSION_ID and must not replace the visible Claude session.
if [ "$KIND" = "codex" ] && { [ -n "${CLAUDECODE:-}" ] || [ -n "${CLAUDE_CODE_ENTRYPOINT:-}" ]; }; then
  exit 0
fi

[ ! -L "$DIR" ] || {
  echo "Agent Signals status directory must not be a symbolic link: $DIR" >&2
  exit 1
}
mkdir -p "$DIR"
[ ! -L "$DIR" ] || {
  echo "Agent Signals status directory became a symbolic link: $DIR" >&2
  exit 1
}
chmod 700 "$DIR"

PAYLOAD="$(cat 2>/dev/null || true)"

# Agent process pid (grandparent of the hook script) — a session liveness proxy.
PID="${AGENT_TRAFFIC_PID:-$(ps -o ppid= -p "$PPID" 2>/dev/null | tr -d ' ')}"
case "$PID" in
  ''|*[!0-9]*) PID=0 ;;
esac

SID="$(printf '%s' "$PAYLOAD" | jq -r '.session_id // .sessionId // empty' 2>/dev/null || true)"
[ -z "$SID" ] && SID="${AGENT_TRAFFIC_SID:-}"
[ -z "$SID" ] && SID="pid-$PID"

# Normal agent ids are filename-safe. Unexpected ids are hashed rather than
# interpolated into a path, so hook input can never escape the status directory.
case "$SID" in
  *[!A-Za-z0-9._:-]*|'')
    FILE_KEY="session-$(printf '%s' "$SID" | shasum -a 256 | awk '{print $1}')"
    ;;
  *)
    if [ "${#SID}" -le 128 ]; then
      FILE_KEY="$SID"
    else
      FILE_KEY="session-$(printf '%s' "$SID" | shasum -a 256 | awk '{print $1}')"
    fi
    ;;
esac

FILE="$DIR/$FILE_KEY.json"

if [ "$STATE" = "end" ]; then
  rm -f "$FILE"
  exit 0
fi

ITERM="${ITERM_SESSION_ID:-}"

# Agent Signals is explicitly iTerm-only. Remove a previous record if the same
# session later reports from Codex Desktop, Terminal.app, an IDE, or another
# context without a valid iTerm session id.
if [ -z "$ITERM" ]; then
  rm -f "$FILE"
  exit 0
fi

CWD="$(printf '%s' "$PAYLOAD" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -z "$CWD" ] && CWD="$PWD"
TS="$(date +%s)"

# Atomic same-directory write. mktemp avoids collisions between concurrent
# hooks for the same session; umask keeps project paths private to the user.
TMP="$(mktemp "$DIR/.agent-signals.XXXXXX")"
trap 'rm -f "$TMP"' EXIT HUP INT TERM
jq -n \
  --arg sid "$SID" \
  --arg state "$STATE" \
  --argjson pid "$PID" \
  --argjson ts "$TS" \
  --arg agent "$KIND" \
  --arg cwd "$CWD" \
  --arg iterm "$ITERM" \
  '{session_id:$sid, state:$state, pid:$pid, ts:$ts, agent:$agent, cwd:$cwd, iterm:$iterm}' > "$TMP"
chmod 600 "$TMP"
mv -f "$TMP" "$FILE"
trap - EXIT HUP INT TERM

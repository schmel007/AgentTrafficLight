#!/bin/sh
# Пишет статус Claude Code сессии в файл для AgentTrafficLight.
# Usage: agent-status.sh <working|waiting|done|end>
set -eu

DIR="${AGENT_TRAFFIC_DIR:-$HOME/.claude/agent-traffic}"
STATE="${1:-}"
[ -z "$STATE" ] && exit 0
mkdir -p "$DIR"

# session_id: из stdin payload (.session_id), иначе env, иначе unknown
PAYLOAD="$(cat 2>/dev/null || true)"
SID="$(printf '%s' "$PAYLOAD" | jq -r '.session_id // empty' 2>/dev/null || true)"
[ -z "$SID" ] && SID="${AGENT_TRAFFIC_SID:-unknown}"

FILE="$DIR/$SID.json"

if [ "$STATE" = "end" ]; then
  rm -f "$FILE"
  exit 0
fi

# pid процесса Claude Code (дед хук-скрипта) — прокси живости сессии
PID="${AGENT_TRAFFIC_PID:-$(ps -o ppid= -p "$PPID" 2>/dev/null | tr -d ' ')}"
[ -z "$PID" ] && PID=0
TS="$(date +%s)"

# Атомарная запись: temp + mv (rename), чтобы консьюмер не прочитал полуфайл
TMP="$FILE.tmp.$$"
jq -n \
  --arg sid "$SID" \
  --arg state "$STATE" \
  --argjson pid "${PID:-0}" \
  --argjson ts "$TS" \
  '{session_id:$sid, state:$state, pid:$pid, ts:$ts}' > "$TMP"
mv -f "$TMP" "$FILE"

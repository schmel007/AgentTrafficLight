#!/bin/sh
# Пишет статус агентской сессии (Claude Code / Codex) в файл для AgentTrafficLight.
# Usage: agent-status.sh <working|waiting|done|end> [claude|codex]
set -eu

DIR="${AGENT_TRAFFIC_DIR:-$HOME/.claude/agent-traffic}"
STATE="${1:-}"
[ -z "$STATE" ] && exit 0
KIND="${2:-claude}"
mkdir -p "$DIR"

PAYLOAD="$(cat 2>/dev/null || true)"

# pid процесса агента (дед хук-скрипта) — прокси живости сессии
PID="${AGENT_TRAFFIC_PID:-$(ps -o ppid= -p "$PPID" 2>/dev/null | tr -d ' ')}"
[ -z "$PID" ] && PID=0

# session_id: из payload, иначе env, иначе pid-<pid> (уникальность даже без session_id, напр. у Codex)
SID="$(printf '%s' "$PAYLOAD" | jq -r '.session_id // .sessionId // empty' 2>/dev/null || true)"
[ -z "$SID" ] && SID="${AGENT_TRAFFIC_SID:-}"
[ -z "$SID" ] && SID="pid-$PID"

FILE="$DIR/$SID.json"

if [ "$STATE" = "end" ]; then
  rm -f "$FILE"
  exit 0
fi

ITERM="${ITERM_SESSION_ID:-}"

# Индикатор считает вкладки iTerm. Codex Desktop тоже выполняет ~/.codex/hooks.json,
# но у него нет ITERM_SESSION_ID; такие события не должны попадать в счётчик.
if [ "$KIND" = "codex" ] && [ -z "$ITERM" ]; then
  rm -f "$FILE"
  exit 0
fi

CWD="$(printf '%s' "$PAYLOAD" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -z "$CWD" ] && CWD="$PWD"
TS="$(date +%s)"

# Атомарная запись: temp + mv (rename), чтобы консьюмер не прочитал полуфайл
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

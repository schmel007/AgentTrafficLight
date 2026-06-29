#!/bin/sh
set -eu
SCRIPT="$(dirname "$0")/agent-status.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

# 1) session_id из stdin, state working, agent по умолчанию claude, iterm из env
echo '{"session_id":"sess-1","cwd":"/x/proj"}' | \
  AGENT_TRAFFIC_DIR="$TMP" AGENT_TRAFFIC_PID=99999 ITERM_SESSION_ID="w0t1:GUID-A" sh "$SCRIPT" working
F="$TMP/sess-1.json"
[ -f "$F" ] || fail "файл не создан"
jq -e '.state=="working" and .pid==99999 and .session_id=="sess-1" and .agent=="claude" and .cwd=="/x/proj" and .iterm=="w0t1:GUID-A" and (.ts|type=="number")' "$F" >/dev/null \
  || fail "содержимое working неверно: $(cat "$F")"

# 2) waiting перезаписывает тот же файл
echo '{"session_id":"sess-1"}' | AGENT_TRAFFIC_DIR="$TMP" AGENT_TRAFFIC_PID=99999 sh "$SCRIPT" waiting
jq -e '.state=="waiting"' "$F" >/dev/null || fail "waiting не записан"

# 3) end удаляет файл
echo '{"session_id":"sess-1"}' | AGENT_TRAFFIC_DIR="$TMP" sh "$SCRIPT" end
[ -f "$F" ] && fail "end не удалил файл" || true

# 4) fallback на AGENT_TRAFFIC_SID когда stdin пустой
printf '' | AGENT_TRAFFIC_DIR="$TMP" AGENT_TRAFFIC_SID=sess-2 AGENT_TRAFFIC_PID=1 sh "$SCRIPT" done
jq -e '.state=="done" and .session_id=="sess-2"' "$TMP/sess-2.json" >/dev/null || fail "fallback SID не сработал"

# 5) session_id со спецсимволом не ломает JSON
echo '{"session_id":"a\"b"}' | AGENT_TRAFFIC_DIR="$TMP" AGENT_TRAFFIC_PID=7 sh "$SCRIPT" working
jq -e '.session_id=="a\"b" and .state=="working"' "$TMP/a\"b.json" >/dev/null || fail "спецсимвол в SID сломал JSON"

# 6) вид агента codex
echo '{"session_id":"cx-1"}' | AGENT_TRAFFIC_DIR="$TMP" AGENT_TRAFFIC_PID=5 sh "$SCRIPT" working codex
jq -e '.agent=="codex"' "$TMP/cx-1.json" >/dev/null || fail "agent=codex не записан"

# 7) без session_id и без AGENT_TRAFFIC_SID → ключ pid-<pid> (нет коллизии unknown)
printf '{}' | AGENT_TRAFFIC_DIR="$TMP" AGENT_TRAFFIC_PID=4242 sh "$SCRIPT" working codex
[ -f "$TMP/pid-4242.json" ] || fail "pid-fallback ключ не создан"
jq -e '.session_id=="pid-4242" and .agent=="codex"' "$TMP/pid-4242.json" >/dev/null || fail "pid-fallback содержимое неверно"

echo "ALL PASS"

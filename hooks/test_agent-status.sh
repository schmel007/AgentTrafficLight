#!/bin/sh
set -eu
SCRIPT="$(dirname "$0")/agent-status.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

# 1) session_id from stdin, state working, agent defaults to claude, iterm from env
echo '{"session_id":"sess-1","cwd":"/x/proj"}' | \
  AGENT_TRAFFIC_DIR="$TMP" AGENT_TRAFFIC_PID=99999 ITERM_SESSION_ID="w0t1:GUID-A" sh "$SCRIPT" working
F="$TMP/sess-1.json"
[ -f "$F" ] || fail "file not created"
jq -e '.state=="working" and .pid==99999 and .session_id=="sess-1" and .agent=="claude" and .cwd=="/x/proj" and .iterm=="w0t1:GUID-A" and (.ts|type=="number")' "$F" >/dev/null \
  || fail "working content is wrong: $(cat "$F")"

# 2) waiting overwrites the same file
echo '{"session_id":"sess-1"}' | AGENT_TRAFFIC_DIR="$TMP" AGENT_TRAFFIC_PID=99999 sh "$SCRIPT" waiting
jq -e '.state=="waiting"' "$F" >/dev/null || fail "waiting not written"

# 3) end deletes the file
echo '{"session_id":"sess-1"}' | AGENT_TRAFFIC_DIR="$TMP" sh "$SCRIPT" end
[ -f "$F" ] && fail "end did not delete the file" || true

# 4) fallback to AGENT_TRAFFIC_SID when stdin is empty
printf '' | AGENT_TRAFFIC_DIR="$TMP" AGENT_TRAFFIC_SID=sess-2 AGENT_TRAFFIC_PID=1 sh "$SCRIPT" done
jq -e '.state=="done" and .session_id=="sess-2"' "$TMP/sess-2.json" >/dev/null || fail "SID fallback did not work"

# 5) session_id with a special character does not break JSON
echo '{"session_id":"a\"b"}' | AGENT_TRAFFIC_DIR="$TMP" AGENT_TRAFFIC_PID=7 sh "$SCRIPT" working
jq -e '.session_id=="a\"b" and .state=="working"' "$TMP/a\"b.json" >/dev/null || fail "special character in SID broke JSON"

# 6) codex agent kind in an iTerm tab
echo '{"session_id":"cx-1"}' | ITERM_SESSION_ID="w0t1:GUID-C" CLAUDECODE= CLAUDE_CODE_ENTRYPOINT= \
  AGENT_TRAFFIC_DIR="$TMP" AGENT_TRAFFIC_PID=5 sh "$SCRIPT" working codex
jq -e '.agent=="codex" and .iterm=="w0t1:GUID-C"' "$TMP/cx-1.json" >/dev/null || fail "agent=codex not written"

# 7) no session_id and no AGENT_TRAFFIC_SID → pid-<pid> key (no "unknown" collision)
printf '{}' | AGENT_TRAFFIC_DIR="$TMP" AGENT_TRAFFIC_PID=4242 sh "$SCRIPT" working
[ -f "$TMP/pid-4242.json" ] || fail "pid-fallback key not created"
jq -e '.session_id=="pid-4242" and .agent=="claude"' "$TMP/pid-4242.json" >/dev/null || fail "pid-fallback content is wrong"

# 8) Codex Desktop without iTerm must not reach the counter and must remove the old record
echo '{"session_id":"cx-desktop"}' | ITERM_SESSION_ID="w0t1:GUID-D" CLAUDECODE= CLAUDE_CODE_ENTRYPOINT= \
  AGENT_TRAFFIC_DIR="$TMP" AGENT_TRAFFIC_PID=6 sh "$SCRIPT" working codex
[ -f "$TMP/cx-desktop.json" ] || fail "codex desktop fixture not created"
echo '{"session_id":"cx-desktop"}' | ITERM_SESSION_ID= CLAUDECODE= CLAUDE_CODE_ENTRYPOINT= \
  AGENT_TRAFFIC_DIR="$TMP" AGENT_TRAFFIC_PID=6 sh "$SCRIPT" done codex
[ -f "$TMP/cx-desktop.json" ] && fail "codex without ITERM_SESSION_ID did not delete the old record" || true

# 9) codex nested inside a Claude Code session must be ignored entirely
echo '{"session_id":"cx-nested"}' | ITERM_SESSION_ID="w0t1:GUID-E" CLAUDE_CODE_ENTRYPOINT=cli CLAUDECODE=1 \
  AGENT_TRAFFIC_DIR="$TMP" AGENT_TRAFFIC_PID=8 sh "$SCRIPT" working codex
[ -f "$TMP/cx-nested.json" ] && fail "nested codex must not write a status file" || true

echo "ALL PASS"

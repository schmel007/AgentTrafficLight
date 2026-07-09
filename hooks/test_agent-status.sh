#!/bin/sh
set -eu

SCRIPT="$(dirname "$0")/agent-status.sh"
ROOT="$(mktemp -d)"
STATUS_DIR="$ROOT/status"
trap 'rm -rf "$ROOT"' EXIT

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

record_for_sid() {
  sid="$1"
  find "$STATUS_DIR" -maxdepth 1 -type f -name '*.json' -exec jq -e --arg sid "$sid" 'select(.session_id == $sid)' {} \; -print | tail -n 1
}

assert_mode() {
  expected="$1"
  path="$2"
  actual="$(stat -f '%Lp' "$path")"
  [ "$actual" = "$expected" ] || fail "mode for $path is $actual, expected $expected"
}

# 1) A normal Claude iTerm event creates a private, valid record.
printf '%s' '{"session_id":"sess-1","cwd":"/x/proj"}' | \
  AGENT_TRAFFIC_DIR="$STATUS_DIR" AGENT_TRAFFIC_PID=99999 ITERM_SESSION_ID="w0t1:AAAA" \
  sh "$SCRIPT" working
F="$(record_for_sid sess-1)"
[ -n "$F" ] || fail "record was not created"
jq -e '.state == "working" and .pid == 99999 and .agent == "claude" and .cwd == "/x/proj" and .iterm == "w0t1:AAAA" and (.ts | type == "number")' "$F" >/dev/null \
  || fail "working record has invalid content"
assert_mode 700 "$STATUS_DIR"
assert_mode 600 "$F"

# 2) A state transition atomically replaces the same record.
printf '%s' '{"session_id":"sess-1"}' | \
  AGENT_TRAFFIC_DIR="$STATUS_DIR" AGENT_TRAFFIC_PID=99999 ITERM_SESSION_ID="w0t1:AAAA" \
  sh "$SCRIPT" waiting
[ "$(record_for_sid sess-1)" = "$F" ] || fail "safe session id changed storage file"
jq -e '.state == "waiting"' "$F" >/dev/null || fail "waiting state was not written"

# 3) Session end removes the record.
printf '%s' '{"session_id":"sess-1"}' | AGENT_TRAFFIC_DIR="$STATUS_DIR" sh "$SCRIPT" end
[ -n "$(record_for_sid sess-1)" ] && fail "end did not remove the record"

# 4) Fallback ids remain deterministic.
printf '' | AGENT_TRAFFIC_DIR="$STATUS_DIR" AGENT_TRAFFIC_SID=sess-2 AGENT_TRAFFIC_PID=1 \
  ITERM_SESSION_ID="w0t1:BBBB" sh "$SCRIPT" 'done'
jq -e '.state == "done" and .session_id == "sess-2"' "$(record_for_sid sess-2)" >/dev/null \
  || fail "AGENT_TRAFFIC_SID fallback failed"
printf '{}' | AGENT_TRAFFIC_DIR="$STATUS_DIR" AGENT_TRAFFIC_PID=4242 \
  ITERM_SESSION_ID="w0t1:CCCC" sh "$SCRIPT" working
[ -n "$(record_for_sid pid-4242)" ] || fail "pid fallback was not created"

# 5) Untrusted session ids are hashed and cannot escape the directory.
printf '%s' '{"session_id":"../escaped","cwd":"/tmp"}' | \
  AGENT_TRAFFIC_DIR="$STATUS_DIR" AGENT_TRAFFIC_PID=7 ITERM_SESSION_ID="w0t1:DDDD" \
  sh "$SCRIPT" working
ESCAPED="$(record_for_sid ../escaped)"
[ -n "$ESCAPED" ] || fail "hashed traversal id was not stored"
[ "$(dirname "$ESCAPED")" = "$STATUS_DIR" ] || fail "traversal id escaped status directory"
[ ! -e "$ROOT/escaped.json" ] || fail "traversal id wrote outside status directory"
case "$(basename "$ESCAPED")" in
  session-*.json) ;;
  *) fail "unsafe session id was not hashed" ;;
esac

# 6) Non-iTerm events from either agent are removed.
for kind in claude codex; do
  sid="outside-$kind"
  printf '{"session_id":"%s"}' "$sid" | AGENT_TRAFFIC_DIR="$STATUS_DIR" AGENT_TRAFFIC_PID=6 \
    ITERM_SESSION_ID="w0t1:EEEE" CLAUDECODE='' CLAUDE_CODE_ENTRYPOINT='' sh "$SCRIPT" working "$kind"
  [ -n "$(record_for_sid "$sid")" ] || fail "$kind fixture was not created"
  printf '{"session_id":"%s"}' "$sid" | AGENT_TRAFFIC_DIR="$STATUS_DIR" AGENT_TRAFFIC_PID=6 \
    ITERM_SESSION_ID='' CLAUDECODE='' CLAUDE_CODE_ENTRYPOINT='' sh "$SCRIPT" 'done' "$kind"
  [ -z "$(record_for_sid "$sid")" ] || fail "$kind non-iTerm event was not removed"
done

# 7) Nested Codex runs inside Claude Code are ignored.
printf '%s' '{"session_id":"cx-nested"}' | AGENT_TRAFFIC_DIR="$STATUS_DIR" AGENT_TRAFFIC_PID=8 \
  ITERM_SESSION_ID="w0t1:FFFF" CLAUDE_CODE_ENTRYPOINT=cli CLAUDECODE=1 \
  sh "$SCRIPT" working codex
[ -z "$(record_for_sid cx-nested)" ] || fail "nested Codex event wrote a record"

# 8) Invalid configuration fails without creating files; malformed pids become zero.
if printf '{}' | AGENT_TRAFFIC_DIR="$STATUS_DIR" ITERM_SESSION_ID="w0t1:AAAA" sh "$SCRIPT" invalid 2>/dev/null; then
  fail "invalid state succeeded"
fi
if printf '{}' | AGENT_TRAFFIC_DIR="$STATUS_DIR" ITERM_SESSION_ID="w0t1:AAAA" sh "$SCRIPT" working invalid 2>/dev/null; then
  fail "invalid agent kind succeeded"
fi
printf '%s' '{"session_id":"bad-pid"}' | AGENT_TRAFFIC_DIR="$STATUS_DIR" AGENT_TRAFFIC_PID=not-a-number \
  ITERM_SESSION_ID="w0t1:AAAA" sh "$SCRIPT" working
jq -e '.pid == 0' "$(record_for_sid bad-pid)" >/dev/null || fail "malformed pid was not normalized"

# 9) Concurrent events never expose partial JSON or shared temp files.
i=0
while [ "$i" -lt 20 ]; do
  printf '%s' '{"session_id":"concurrent"}' | AGENT_TRAFFIC_DIR="$STATUS_DIR" AGENT_TRAFFIC_PID="$i" \
    ITERM_SESSION_ID="w0t1:ABCD" sh "$SCRIPT" working &
  i=$((i + 1))
done
wait
CONCURRENT="$(record_for_sid concurrent)"
jq -e '.session_id == "concurrent" and .state == "working"' "$CONCURRENT" >/dev/null \
  || fail "concurrent record is invalid"
[ "$(find "$STATUS_DIR" -maxdepth 1 -name '.agent-signals.*' | wc -l | tr -d ' ')" = "0" ] \
  || fail "temporary files leaked"

# 10) A symbolic-link status directory is rejected without touching its target.
SYMLINK_TARGET="$ROOT/symlink-target"
SYMLINK_DIR="$ROOT/status-link"
mkdir -p "$SYMLINK_TARGET"
ln -s "$SYMLINK_TARGET" "$SYMLINK_DIR"
if printf '%s' '{"session_id":"symlink-dir"}' | AGENT_TRAFFIC_DIR="$SYMLINK_DIR" \
  AGENT_TRAFFIC_PID=9 ITERM_SESSION_ID="w0t1:ABCD" sh "$SCRIPT" working 2>/dev/null; then
  fail "symbolic-link status directory was accepted"
fi
[ ! -e "$SYMLINK_TARGET/symlink-dir.json" ] || fail "symbolic-link target was modified"

echo "ALL PASS"

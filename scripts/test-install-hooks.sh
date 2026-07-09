#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
HOME_DIR="$TMP/home with space's quote"
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

mkdir -p "$HOME_DIR/.claude" "$HOME_DIR/.codex"
cat > "$HOME_DIR/.claude/settings.json" <<'JSON'
{
  "theme": "dark",
  "hooks": {
    "Stop": [
      {"hooks": [{"type": "command", "command": "printf unrelated"}]},
      {"hooks": [{"type": "command", "command": "[ -x '/old/AgentTrafficLight/hooks/agent-status.sh' ] && /old/AgentTrafficLight/hooks/agent-status.sh done || true"}]}
    ]
  }
}
JSON
cat > "$HOME_DIR/.codex/hooks.json" <<'JSON'
{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"printf unrelated"}]}]}}
JSON
claude_original_hash="$(shasum -a 256 "$HOME_DIR/.claude/settings.json" | awk '{print $1}')"
codex_original_hash="$(shasum -a 256 "$HOME_DIR/.codex/hooks.json" | awk '{print $1}')"

HOME="$HOME_DIR" sh "$ROOT_DIR/scripts/install-hooks.sh"
HOME="$HOME_DIR" sh "$ROOT_DIR/scripts/install-hooks.sh" --check

HOOK="$HOME_DIR/.local/share/agent-signals/agent-status.sh"
[ -x "$HOOK" ] || fail "hook was not installed"
[ "$(stat -f '%Lp' "$HOOK")" = 755 ] || fail "installed hook mode is not 755"
[ "$(stat -f '%Lp' "$HOME_DIR/.claude/settings.json")" = 600 ] || fail "Claude settings mode is not 600"
[ "$(stat -f '%Lp' "$HOME_DIR/.codex/hooks.json")" = 600 ] || fail "Codex hooks mode is not 600"

jq -e '.theme == "dark"' "$HOME_DIR/.claude/settings.json" >/dev/null || fail "Claude settings were not preserved"
jq -e '[.hooks.Stop[]?.hooks[]? | select(.command == "printf unrelated")] | length == 1' \
  "$HOME_DIR/.claude/settings.json" >/dev/null || fail "unrelated Claude hook was not preserved"
jq -e '[.hooks.SessionStart[]?.hooks[]? | select(.command == "printf unrelated")] | length == 1' \
  "$HOME_DIR/.codex/hooks.json" >/dev/null || fail "unrelated Codex hook was not preserved"

# A state mapping mismatch must fail verification even when counts and paths still match.
cp -p "$HOME_DIR/.codex/hooks.json" "$TMP/codex-hooks-good.json"
jq '(.hooks.PermissionRequest[]?.hooks[]?
     | select((.command? // "") | contains("AGENT_SIGNALS_HOOK=1"))
     | .command) |= sub(" waiting codex$"; " working codex")' \
  "$HOME_DIR/.codex/hooks.json" > "$TMP/codex-hooks-bad.json"
chmod 600 "$TMP/codex-hooks-bad.json"
mv "$TMP/codex-hooks-bad.json" "$HOME_DIR/.codex/hooks.json"
if HOME="$HOME_DIR" sh "$ROOT_DIR/scripts/install-hooks.sh" --check >/dev/null 2>&1; then
  fail "installer check accepted an incorrect state mapping"
fi
mv "$TMP/codex-hooks-good.json" "$HOME_DIR/.codex/hooks.json"

# Reinstalling is idempotent and creates recoverable backups.
HOME="$HOME_DIR" sh "$ROOT_DIR/scripts/install-hooks.sh" >/dev/null
HOME="$HOME_DIR" sh "$ROOT_DIR/scripts/install-hooks.sh" --check >/dev/null
[ -f "$HOME_DIR/.claude/settings.json.agent-signals-backup" ] || fail "Claude backup was not created"
[ -f "$HOME_DIR/.codex/hooks.json.agent-signals-backup" ] || fail "Codex backup was not created"
[ "$(shasum -a 256 "$HOME_DIR/.claude/settings.json.agent-signals-backup" | awk '{print $1}')" = "$claude_original_hash" ] \
  || fail "Claude backup did not preserve the original settings"
[ "$(shasum -a 256 "$HOME_DIR/.codex/hooks.json.agent-signals-backup" | awk '{print $1}')" = "$codex_original_hash" ] \
  || fail "Codex backup did not preserve the original settings"

# Execute the installed command from a path containing spaces.
COMMAND="$(jq -r '.hooks.UserPromptSubmit[] | select(any(.hooks[]; (.command // "") | contains("AGENT_SIGNALS_HOOK=1"))) | .hooks[0].command' "$HOME_DIR/.codex/hooks.json")"
STATUS_DIR="$TMP/status"
printf '%s' '{"session_id":"installer-smoke","cwd":"/tmp/project"}' | HOME="$HOME_DIR" \
  AGENT_TRAFFIC_DIR="$STATUS_DIR" AGENT_TRAFFIC_PID=42 ITERM_SESSION_ID="w0t1:AAAA" sh -c "$COMMAND"
jq -e '.session_id == "installer-smoke" and .agent == "codex"' "$STATUS_DIR/installer-smoke.json" >/dev/null \
  || fail "installed Codex command did not execute"

# Invalid JSON fails before modifying either configuration.
INVALID_HOME="$TMP/invalid-home"
mkdir -p "$INVALID_HOME/.claude" "$INVALID_HOME/.codex"
printf '{invalid\n' > "$INVALID_HOME/.claude/settings.json"
printf '{}\n' > "$INVALID_HOME/.codex/hooks.json"
before="$(shasum -a 256 "$INVALID_HOME/.codex/hooks.json")"
if HOME="$INVALID_HOME" sh "$ROOT_DIR/scripts/install-hooks.sh" >/dev/null 2>&1; then
  fail "installer accepted invalid Claude settings"
fi
[ "$before" = "$(shasum -a 256 "$INVALID_HOME/.codex/hooks.json")" ] || fail "installer partially modified valid config"

# Uninstall removes only Agent Signals entries.
HOME="$HOME_DIR" sh "$ROOT_DIR/scripts/install-hooks.sh" --uninstall >/dev/null
[ ! -e "$HOOK" ] || fail "installed hook was not removed"
[ "$(jq '[.hooks[]?[]?.hooks[]? | select((.command? // "") | contains("AGENT_SIGNALS_HOOK=1"))] | length' "$HOME_DIR/.claude/settings.json")" = 0 ] \
  || fail "Claude Agent Signals hooks remain after uninstall"
jq -e '.theme == "dark" and ([.hooks.Stop[]?.hooks[]? | select(.command == "printf unrelated")] | length == 1)' \
  "$HOME_DIR/.claude/settings.json" >/dev/null || fail "uninstall removed unrelated settings"

echo "ALL PASS"

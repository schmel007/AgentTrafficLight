#!/bin/sh
# Installs Agent Signals lifecycle hooks for Claude Code and Codex.
set -eu

umask 077

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/agent-status.sh" ]; then
  SOURCE_HOOK="$SCRIPT_DIR/agent-status.sh"
else
  SOURCE_HOOK="$SCRIPT_DIR/../hooks/agent-status.sh"
fi

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
INSTALL_DIR="${AGENT_SIGNALS_HOME:-$HOME/.local/share/agent-signals}"
TARGET_HOOK="$INSTALL_DIR/agent-status.sh"
CLAUDE_SETTINGS="$CLAUDE_DIR/settings.json"
CODEX_HOOKS="$CODEX_DIR/hooks.json"

usage() {
  cat <<'USAGE'
Usage:
  install-hooks.sh             Install or update hooks
  install-hooks.sh --check     Verify the installation
  install-hooks.sh --uninstall Remove only Agent Signals hooks
USAGE
}

fail() {
  echo "Agent Signals installer: $1" >&2
  exit 1
}

require_jq() {
  command -v jq >/dev/null 2>&1 || fail "jq is required. Install jq and run this command again."
}

validate_config() {
  file="$1"
  [ -e "$file" ] || return 0
  [ -f "$file" ] || fail "$file is not a regular file"
  jq -e '
    type == "object"
    and ((.hooks // {}) | type == "object")
    and all((.hooks // {})[]; type == "array")
  ' "$file" >/dev/null 2>&1 || fail "$file is not valid hook configuration JSON"
}

shell_quote() {
  escaped="$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
  printf "'%s'" "$escaped"
}

render_config() {
  file="$1"
  agent="$2"
  output="$3"
  base="AGENT_SIGNALS_HOOK=1 $(shell_quote "$TARGET_HOOK")"
  working="$base working"
  waiting="$base waiting"
  completed="$base done"
  end="$base end"
  if [ "$agent" = "codex" ]; then
    working="$working codex"
    waiting="$waiting codex"
    completed="$completed codex"
  fi

  if [ -e "$file" ]; then
    input="$file"
  else
    input=/dev/null
  fi

  if [ "$input" = /dev/null ]; then
    printf '{}\n' | jq \
      --arg working "$working" --arg waiting "$waiting" --arg completed "$completed" --arg end "$end" \
      --arg agent "$agent" -f "$SCRIPT_DIR/install-hooks.jq" > "$output"
  else
    jq \
      --arg working "$working" --arg waiting "$waiting" --arg completed "$completed" --arg end "$end" \
      --arg agent "$agent" -f "$SCRIPT_DIR/install-hooks.jq" "$input" > "$output"
  fi
}

backup_and_replace() {
  file="$1"
  prepared="$2"
  if [ -e "$file" ] && [ ! -e "$file.agent-signals-backup" ]; then
    cp -p "$file" "$file.agent-signals-backup"
  fi
  chmod 600 "$prepared"
  mv -f "$prepared" "$file"
}

managed_hook_count() {
  file="$1"
  jq '[.hooks[]?[]?.hooks[]? | select((.command? // "") | contains("AGENT_SIGNALS_HOOK=1"))] | length' "$file"
}

check_installation() {
  quoted_target_hook="$(shell_quote "$TARGET_HOOK")"
  base="AGENT_SIGNALS_HOOK=1 $quoted_target_hook"
  [ -x "$TARGET_HOOK" ] || fail "installed hook is missing or not executable: $TARGET_HOOK"
  [ -f "$SOURCE_HOOK" ] || fail "source hook is missing: $SOURCE_HOOK"
  cmp -s "$SOURCE_HOOK" "$TARGET_HOOK" || fail "installed hook does not match this installer"
  validate_config "$CLAUDE_SETTINGS"
  validate_config "$CODEX_HOOKS"
  [ -f "$CLAUDE_SETTINGS" ] || fail "Claude Code settings are missing"
  [ -f "$CODEX_HOOKS" ] || fail "Codex hooks are missing"
  [ "$(stat -f '%Lp' "$INSTALL_DIR")" = 700 ] || fail "install directory permissions are not 700"
  [ "$(stat -f '%Lp' "$TARGET_HOOK")" = 755 ] || fail "installed hook permissions are not 755"
  [ "$(stat -f '%Lp' "$CLAUDE_SETTINGS")" = 600 ] || fail "Claude Code settings permissions are not 600"
  [ "$(stat -f '%Lp' "$CODEX_HOOKS")" = 600 ] || fail "Codex hooks permissions are not 600"
  [ "$(managed_hook_count "$CLAUDE_SETTINGS")" = 5 ] || fail "Claude Code hook set is incomplete"
  [ "$(managed_hook_count "$CODEX_HOOKS")" = 4 ] || fail "Codex hook set is incomplete"
  jq -e \
    --arg working "$base working" --arg waiting "$base waiting" \
    --arg completed "$base done" --arg end "$base end" '
    def managed($event):
      [.hooks[$event][]?.hooks[]?
       | select((.command? // "") | contains("AGENT_SIGNALS_HOOK=1"))];
    (managed("UserPromptSubmit") | map(.command)) == [$working]
    and (managed("PostToolUse") | map(.command)) == [$working]
    and (managed("PermissionRequest") | map(.command)) == [$waiting]
    and (managed("Stop") | map(.command)) == [$completed]
    and (managed("SessionEnd") | map(.command)) == [$end]
    and all(.hooks[]?[]?.hooks[]?
            | select((.command? // "") | contains("AGENT_SIGNALS_HOOK=1"));
            .type == "command" and .timeout == 10)
  ' "$CLAUDE_SETTINGS" >/dev/null || fail "Claude Code hook mapping is incorrect"
  jq -e \
    --arg working "$base working codex" --arg waiting "$base waiting codex" \
    --arg completed "$base done codex" '
    def managed($event):
      [.hooks[$event][]?.hooks[]?
       | select((.command? // "") | contains("AGENT_SIGNALS_HOOK=1"))];
    (managed("UserPromptSubmit") | map(.command)) == [$working]
    and (managed("PostToolUse") | map(.command)) == [$working]
    and (managed("PermissionRequest") | map(.command)) == [$waiting]
    and (managed("Stop") | map(.command)) == [$completed]
    and all(.hooks[]?[]?.hooks[]?
            | select((.command? // "") | contains("AGENT_SIGNALS_HOOK=1"));
            .type == "command" and .timeout == 10)
  ' "$CODEX_HOOKS" >/dev/null || fail "Codex hook mapping is incorrect"
  echo "Agent Signals hooks are installed correctly."
}

uninstall_hooks() {
  validate_config "$CLAUDE_SETTINGS"
  validate_config "$CODEX_HOOKS"
  for file in "$CLAUDE_SETTINGS" "$CODEX_HOOKS"; do
    [ -e "$file" ] || continue
    tmp="$(mktemp "$file.tmp.XXXXXX")"
    jq -f "$SCRIPT_DIR/remove-hooks.jq" "$file" > "$tmp"
    backup_and_replace "$file" "$tmp"
  done
  rm -f "$TARGET_HOOK"
  rmdir "$INSTALL_DIR" 2>/dev/null || true
  echo "Agent Signals hooks were removed."
}

require_jq

case "${1:-}" in
  --help|-h)
    usage
    exit 0
    ;;
  --check)
    check_installation
    exit 0
    ;;
  --uninstall)
    uninstall_hooks
    exit 0
    ;;
  '') ;;
  *)
    usage >&2
    exit 2
    ;;
esac

[ -f "$SOURCE_HOOK" ] || fail "agent-status.sh was not found next to the installer"
validate_config "$CLAUDE_SETTINGS"
validate_config "$CODEX_HOOKS"

mkdir -p "$CLAUDE_DIR" "$CODEX_DIR" "$INSTALL_DIR"
chmod 700 "$INSTALL_DIR"

claude_tmp="$(mktemp "$CLAUDE_SETTINGS.tmp.XXXXXX")"
codex_tmp="$(mktemp "$CODEX_HOOKS.tmp.XXXXXX")"
trap 'rm -f "$claude_tmp" "$codex_tmp"' EXIT HUP INT TERM
render_config "$CLAUDE_SETTINGS" claude "$claude_tmp"
render_config "$CODEX_HOOKS" codex "$codex_tmp"

install -m 755 "$SOURCE_HOOK" "$TARGET_HOOK"
backup_and_replace "$CLAUDE_SETTINGS" "$claude_tmp"
backup_and_replace "$CODEX_HOOKS" "$codex_tmp"
trap - EXIT HUP INT TERM

check_installation
echo "For Codex, open /hooks once and trust the new Agent Signals hook definitions."

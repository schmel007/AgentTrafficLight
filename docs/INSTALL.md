# Install Agent Signals

## Requirements

- macOS 13 or later
- iTerm2
- Claude Code and/or Codex
- `jq`

## Install

1. Open the extracted `Agent Signals` folder.
2. Run the hook installer:

   ```bash
   ./install-hooks.sh
   ./install-hooks.sh --check
   ```

3. Move `Agent Signals.app` to `/Applications` and open it.
4. In Codex, open `/hooks`, review the new Agent Signals definitions, and trust them.
   Codex intentionally skips new or changed command hooks until they are trusted.
5. Start a Claude Code or Codex session in iTerm and submit a prompt. The menu bar signal
   should change from `💤` to `🟡`.

The installer:

- copies the hook to `~/.local/share/agent-signals/agent-status.sh`;
- merges Agent Signals entries into `~/.claude/settings.json` and `~/.codex/hooks.json`
  (or `$CODEX_HOME/hooks.json` when `CODEX_HOME` is set) without replacing unrelated settings;
- creates `*.agent-signals-backup` files before replacing existing configuration;
- can be run repeatedly without duplicating hooks.

Claude Code reloads settings changes automatically. Use `/hooks` in Claude Code to inspect
the installed entries. See the official [Claude Code hooks reference](https://code.claude.com/docs/en/hooks)
and [Codex hooks reference](https://learn.chatgpt.com/docs/hooks) for the underlying lifecycle
contracts.

## Uninstall

```bash
./install-hooks.sh --uninstall
```

This removes only Agent Signals hook handlers and the installed hook script. Unrelated Claude
Code and Codex settings are preserved.

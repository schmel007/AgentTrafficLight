# Privacy

Agent Signals is a local-only utility.

## Data Collected

The app reads local JSON status files produced by the hook script:

```text
~/.claude/agent-traffic/
```

Those files may contain:

- agent type;
- session id;
- process id;
- timestamp;
- current working directory;
- iTerm session id.

The app also asks iTerm for open tab/session names when Automation permission is granted.

## Network

Agent Signals does not send app telemetry, status records, project paths, or tab names to
any server.

The release script uses Apple notarization services when maintainers build a release. The
installed app does not use that path.

## Storage

Agent Signals reads and deletes only its status files under `~/.claude/agent-traffic/`.
The hook script writes those files. Finished or stale records may be removed as part of
normal cleanup.

## Permissions

macOS may ask for Automation permission so Agent Signals can inspect and focus iTerm tabs.
If permission is denied, the app still shows status from local files but tab names and
focus behavior are limited.

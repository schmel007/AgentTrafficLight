def is_agent_signals:
  ((.command? // "") | contains("AGENT_SIGNALS_HOOK=1"))
  or (
    ((.command? // "") | contains("agent-status.sh"))
    and ((.command? // "") | contains("AgentTrafficLight"))
  );

def clean_groups:
  map(.hooks = ((.hooks // []) | map(select(is_agent_signals | not))))
  | map(select((.hooks | length) > 0));

def clean_hooks:
  (.hooks // {})
  | with_entries(.value |= clean_groups)
  | with_entries(select((.value | length) > 0));

def group($command; $matcher):
  if $matcher == "" then
    {"hooks": [{"type": "command", "command": $command, "timeout": 10}]}
  else
    {"matcher": $matcher, "hooks": [{"type": "command", "command": $command, "timeout": 10}]}
  end;

.hooks = clean_hooks
| .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) + [group($working; "")])
| .hooks.PostToolUse = ((.hooks.PostToolUse // []) + [group($working; "*")])
| .hooks.PermissionRequest = ((.hooks.PermissionRequest // []) + [group($waiting; "*")])
| .hooks.Stop = ((.hooks.Stop // []) + [group($completed; "")])
| if $agent == "claude" then
    .hooks.SessionEnd = ((.hooks.SessionEnd // []) + [group($end; "")])
  else
    .
  end

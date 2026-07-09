def is_agent_signals:
  ((.command? // "") | contains("AGENT_SIGNALS_HOOK=1"))
  or (
    ((.command? // "") | contains("agent-status.sh"))
    and ((.command? // "") | contains("AgentTrafficLight"))
  );

def clean_groups:
  map(.hooks = ((.hooks // []) | map(select(is_agent_signals | not))))
  | map(select((.hooks | length) > 0));

.hooks = (
  (.hooks // {})
  | with_entries(.value |= clean_groups)
  | with_entries(select((.value | length) > 0))
)
| if (.hooks | length) == 0 then del(.hooks) else . end

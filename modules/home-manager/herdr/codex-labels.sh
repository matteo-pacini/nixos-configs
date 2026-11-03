# Codex hook (SessionStart, Stop, PostToolUse) for hosts with the herdr-app
# agent-tree mod. Inside a herdr-app terminal, sets the labels Claude Code's
# statusLine sets (model, effort, context, version) from the session's rollout
# log, for the mod to draw. Codex reports no prompt-cache expiry, so there is
# no cache label. Prints nothing: Codex reads a hook's stdout.
input=$(cat)
[ -n "${HC_TERMINAL_ID:-}" ] || exit 0

IFS=$'\037' read -r session transcript model <<EOF
$(printf '%s' "$input" | jq -r '[.session_id // "", .transcript_path // "", .model // ""] | join("\u001f")')
EOF

effort="" version="" pct="" ktokens=""
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  version=$(head -n 1 "$transcript" | jq -r 'select(.type == "session_meta") | .payload.cli_version // ""')
  effort=$(grep '"type":"turn_context"' "$transcript" | tail -n 1 | jq -r '.payload.effort // ""')
  # Context as Codex's own status line counts it: the first 12000 tokens
  # (system prompt and tools) are a baseline that never counts as used.
  IFS=$'\037' read -r pct ktokens <<EOF
$(grep '"type":"token_count"' "$transcript" | tail -n 1 | jq -r '
  .payload as $p
  | ($p.info.model_context_window // 0) as $window
  | ($p.info.last_token_usage.total_tokens // 0) as $used
  | (if $window > 12000
      then ([($used - 12000), 0] | max) * 100 / ($window - 12000) | [., 100] | min | round | tostring
      else "" end) as $pct
  | [$pct, (if $pct == "" then "" else ($used / 1000 | floor | tostring) end)]
  | join("\u001f")')
EOF
fi

# An empty value removes the label.
hc label "$HC_TERMINAL_ID" "codex.session=$session" "agent.model=$model" "agent.effort=$effort" \
  "agent.version=$version" "agent.ctx=$pct" "agent.ctxk=$ktokens" >/dev/null 2>&1 || true

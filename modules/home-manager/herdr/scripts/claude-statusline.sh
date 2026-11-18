# Claude Code statusLine command for hosts with the herdr-app agent-list mod.
# Renders the in-pane status line with ccstatusline and, inside a herdr-app
# terminal, sets context usage, prompt-cache expiry and lifetime, model, effort
# and version as terminal labels for the mods to draw. They count the cache
# down themselves.
input=$(cat)

if [ -n "${HC_TERMINAL_ID:-}" ]; then
  # Unit separator, not tab: read collapses runs of IFS whitespace, which
  # would shift fields whenever one of them is empty.
  # Expiry comes from Claude Code, not the transcript: requests that write no
  # transcript entry (the away summary) refresh the cache too. A null expiry
  # with caching observed means the last response missed the cache: 0, cold.
  IFS=$'\037' read -r pct ktokens cache_until cache_ttl model effort version <<EOF
$(printf '%s' "$input" | jq -r '
  [ (.context_window.used_percentage // "" | tostring)
  , ((.context_window.total_input_tokens // 0) / 1000 | floor | tostring)
  , (.prompt_cache
      | if . == null or .caching_observed == false then ""
        else (.expires_at // 0 | floor | tostring) end)
  , (.prompt_cache | if . == null or .caching_observed == false then "" else .ttl // "" end)
  , (.model.display_name // "")
  , (.effort.level // "")
  , (.version // "")
  ] | join("\u001f")')
EOF

  # An empty value removes the label.
  hc label "$HC_TERMINAL_ID" "agent.ctx=${pct%%.*}" "agent.ctxk=${pct:+$ktokens}" \
    "agent.cache_until=$cache_until" "agent.cache_ttl=$cache_ttl" "agent.model=$model" \
    "agent.effort=$effort" "agent.version=$version" \
    >/dev/null 2>&1 || true
fi

printf '%s' "$input" | npx -y ccstatusline@latest

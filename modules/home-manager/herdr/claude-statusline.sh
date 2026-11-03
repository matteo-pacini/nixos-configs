# Claude Code statusLine command for hosts with the herdr-app agent-tree mod.
# Renders the in-pane status line with ccstatusline and, inside a herdr-app
# terminal, sets context usage and prompt-cache expiry as terminal labels for
# the mod to draw. The mod counts the cache down itself.
input=$(cat)

if [ -n "${HC_TERMINAL_ID:-}" ]; then
  # Unit separator, not tab: read collapses runs of IFS whitespace, which
  # would shift fields whenever one of them is empty.
  IFS=$'\037' read -r pct ktokens transcript <<EOF
$(printf '%s' "$input" | jq -r '
  [ (.context_window.used_percentage // "" | tostring)
  , ((.context_window.total_input_tokens // 0) / 1000 | floor | tostring)
  , (.transcript_path // "")
  ] | join("\u001f")')
EOF

  # Main-thread cache TTL is 1h on a subscription unless forced down to 5m.
  ttl=3600
  if [ -n "${FORCE_PROMPT_CACHING_5M:-}" ] || [ "${CLAUDE_CODE_PROMPT_CACHE_TTL:-}" = "5m" ]; then
    ttl=300
  fi

  # The last API call refreshed the cache, and its reply is the newest
  # assistant entry. Read from the end: transcripts grow to many MB and this
  # runs every refreshInterval. tac sits in a process substitution because
  # grep -m1 exits early and, under pipefail, its SIGPIPE would fail the read.
  cache_until=""
  if [ -r "$transcript" ]; then
    last=$(grep -m1 '"type":"assistant"' < <(tac "$transcript") |
      jq -r '.timestamp // empty | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601' 2>/dev/null) || last=""
    [ -n "$last" ] && cache_until=$((last + ttl))
  fi

  # An empty value removes the label.
  hc label "$HC_TERMINAL_ID" "agent.ctx=${pct%%.*}" "agent.ctxk=${pct:+$ktokens}" \
    "agent.cache_until=$cache_until" >/dev/null 2>&1 || true
fi

printf '%s' "$input" | npx -y ccstatusline@latest

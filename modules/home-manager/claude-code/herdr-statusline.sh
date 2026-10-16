# Claude Code statusLine command. Renders the in-pane status line with
# ccstatusline and, when running inside a herdr pane, reports model, effort,
# context usage and prompt-cache expiry through herdr-agent-report (see
# modules/home-manager/herdr.nix for the sidebar rows that consume them).
input=$(cat)

if [ "${HERDR_ENV:-}" = "1" ] && command -v herdr-agent-report >/dev/null 2>&1; then
  # display_name carries a parenthetical variant ("Opus 5 (1M context)") that
  # would collide with the effort parenthetical, so drop it.
  # Unit separator, not tab: read collapses runs of IFS whitespace, which
  # would shift fields whenever one of them is empty.
  IFS=$'\037' read -r model effort pct ktokens transcript <<EOF
$(printf '%s' "$input" | jq -r '
  [ (.model.display_name // "" | sub(" *\\([^)]*\\)$"; ""))
  , (.effort.level // "")
  , (.context_window.used_percentage // "" | tostring)
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
  # runs every refreshInterval.
  cache_until=""
  if [ -r "$transcript" ]; then
    last=$(tac "$transcript" | grep -m1 '"type":"assistant"' |
      jq -r '.timestamp // empty | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601' 2>/dev/null) || last=""
    [ -n "$last" ] && cache_until=$((last + ttl))
  fi

  herdr-agent-report --agent claude --model "$model" --effort "$effort" \
    ${pct:+--pct "$pct"} ${pct:+--ktokens "$ktokens"} \
    ${cache_until:+--cache-until "$cache_until" --cache-mode countdown} || true
fi

printf '%s' "$input" | npx -y ccstatusline@latest

# Codex hook (Stop, PostToolUse): reads the session rollout named in the
# hook input and reports model, effort, context usage and prompt-cache expiry
# to the herdr sidebar through herdr-agent-report. Prints nothing: Codex
# parses hook stdout as a decision.

[ "${HERDR_ENV:-}" = "1" ] && command -v herdr-agent-report >/dev/null 2>&1 || exit 0

transcript=$(jq -r '.transcript_path // empty' 2>/dev/null) || exit 0
[ -r "$transcript" ] || exit 0

# Unit separator, not tab: read collapses runs of IFS whitespace, which
# would shift fields whenever one of them is empty.
IFS=$'\037' read -r model effort <<EOF
$(grep -m1 '"type":"turn_context"' < <(tac "$transcript") |
  jq -r '[.payload.model // "", .payload.effort // ""] | join("\u001f")')
EOF

# The newest token_count with usage is the latest API call, which is also
# when the cache was last refreshed. GPT-5.6 and later keep it for 30
# minutes after each write or reuse. tac sits in a process substitution
# because grep -m1 exits early and, under pipefail, its SIGPIPE would fail
# the read.
IFS=$'\037' read -r pct ktokens cache_until <<EOF
$(grep -m1 '"last_token_usage"' < <(tac "$transcript") |
  jq -r '
    .payload.info as $i
    | [ ($i.last_token_usage.input_tokens * 100 / $i.model_context_window | floor | tostring)
      , ($i.last_token_usage.input_tokens / 1000 | floor | tostring)
      , (.timestamp | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601 + 1800 | tostring)
      ] | join("\u001f")' 2>/dev/null)
EOF

herdr-agent-report --agent codex --model "$model" --effort "$effort" \
  ${pct:+--pct "$pct" --ktokens "$ktokens"} \
  ${cache_until:+--cache-until "$cache_until" --cache-mode clock} || true

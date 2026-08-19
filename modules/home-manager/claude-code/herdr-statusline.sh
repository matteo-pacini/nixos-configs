# Claude Code statusLine command. Renders the in-pane status line with
# ccstatusline and, when running inside a herdr pane, mirrors model/effort
# and context usage into that pane's herdr metadata (see modules/home-manager/herdr.nix
# for the sidebar rows that consume them).
input=$(cat)

if [ "${HERDR_ENV:-}" = "1" ] && [ -n "${HERDR_PANE_ID:-}" ] && command -v herdr >/dev/null 2>&1; then
  # display_name carries a parenthetical variant ("Opus 5 (1M context)") that
  # would collide with the effort parenthetical, so drop it.
  # Unit separator, not tab: read collapses runs of IFS whitespace, which
  # would shift fields whenever one of them is empty.
  IFS=$'\037' read -r model effort pct ktokens <<EOF
$(printf '%s' "$input" | jq -r '
  [ (.model.display_name // "" | sub(" *\\([^)]*\\)$"; "") | ascii_downcase)
  , (.effort.level // "")
  , (.context_window.used_percentage // "" | tostring)
  , ((.context_window.total_input_tokens // 0) / 1000 | floor | tostring)
  ] | join("\u001f")')
EOF

  label="claude${model:+ - $model}${effort:+ ($effort)}"

  if [ -n "$pct" ]; then
    context_arg=(--token "context=⛁ $pct% (${ktokens}k)")
  else
    context_arg=(--clear-token context)
  fi

  # ttl outlives refreshInterval so the row clears shortly after Claude exits.
  herdr pane report-metadata "$HERDR_PANE_ID" \
    --source claude-statusline \
    --agent claude \
    --display-agent "$label" \
    "${context_arg[@]}" \
    --ttl-ms 60000 >/dev/null 2>&1 || true
fi

printf '%s' "$input" | npx -y ccstatusline@latest

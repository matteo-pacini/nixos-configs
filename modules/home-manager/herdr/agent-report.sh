# herdr-agent-report: publishes an agent pane's sidebar tokens to herdr.
#
#   herdr-agent-report --agent claude|codex|opencode --model NAME
#     [--effort LEVEL] [--pct N] [--ktokens N]
#     [--cache-until EPOCH --cache-mode countdown|clock]
#
# Sets $title, $model, one of $ctx_ok/$ctx_warn/$ctx_hot, $ctxk and $cache,
# which the rows_by_agent layout in modules/home-manager/herdr.nix renders.
# countdown suits callers that re-run on a timer (minutes left, then "cold");
# clock suits callers that only run on agent events (fixed expiry time, and
# herdr drops the token itself once the cache has expired).
# No-ops outside a herdr pane. Never fails the caller.

[ "${HERDR_ENV:-}" = "1" ] && [ -n "${HERDR_PANE_ID:-}" ] || exit 0

agent="" model="" effort="" pct="" ktokens="" cache_until="" cache_mode=""
while [ $# -gt 0 ]; do
  case "$1" in
    --agent) agent=$2 ;;
    --model) model=$2 ;;
    --effort) effort=$2 ;;
    --pct) pct=$2 ;;
    --ktokens) ktokens=$2 ;;
    --cache-until) cache_until=$2 ;;
    --cache-mode) cache_mode=$2 ;;
    *) exit 0 ;;
  esac
  shift 2 || exit 0
done

case "$agent" in
  claude) glyph=$'' ;;   # nf-cod-claude
  codex) glyph=$'' ;;    # nf-cod-openai
  opencode) glyph=$'' ;; # nf-cod-terminal
  *) exit 0 ;;
esac

# Name falls back from the pane's herdr label to its terminal title to its
# position, so an unnamed pane still has something to click on.
name=$(herdr pane get "$HERDR_PANE_ID" 2>/dev/null | jq -r '
  .result.pane
  | (.label // "") as $label
  | (.terminal_title_stripped // "") as $title
  | if $label != "" then $label
    elif $title != "" then (if ($title | length) > 24 then $title[:23] + "…" else $title end)
    else .pane_id end') || name=""
[ -n "$name" ] || name=$HERDR_PANE_ID

args=(--token "title=$glyph $name" --token "model=$model${effort:+ ($effort)}")

# The colour band is chosen here rather than by a numeric herdr rule: those
# parse the whole value as a number, which would rule out the "%" suffix.
# Bands track Claude's auto-compact at 80%: amber from half, red within ten
# points of it.
if [ -n "$pct" ]; then
  pct=${pct%%.*}
  if [ "$pct" -ge 70 ]; then band=hot
  elif [ "$pct" -ge 50 ]; then band=warn
  else band=ok
  fi
  for b in ok warn hot; do
    if [ "$b" = "$band" ]; then
      args+=(--token "ctx_$b=$pct%")
    else
      args+=(--clear-token "ctx_$b")
    fi
  done
else
  args+=(--clear-token ctx_ok --clear-token ctx_warn --clear-token ctx_hot)
fi

if [ -n "$ktokens" ]; then
  args+=(--token "ctxk=⛁ ${ktokens}k")
else
  args+=(--clear-token ctxk)
fi

now=$(date +%s)
cache_ttl_args=()
if [ -z "$cache_until" ]; then
  args+=(--clear-token cache)
elif [ "$cache_mode" = clock ]; then
  left=$((cache_until - now))
  if [ "$left" -gt 0 ]; then
    cache_ttl_args=(--token "cache=cache →$(date -d "@$cache_until" +%H:%M)" --ttl-ms "$((left * 1000))")
  else
    args+=(--clear-token cache)
  fi
else
  left=$((cache_until - now))
  if [ "$left" -le 0 ]; then cache="cache cold"
  elif [ "$left" -lt 60 ]; then cache="cache <1m"
  else cache="cache $((left / 60))m"
  fi
  args+=(--token "cache=$cache")
fi

herdr pane report-metadata "$HERDR_PANE_ID" \
  --source "$agent-rows" --agent "$agent" "${args[@]}" >/dev/null 2>&1 || true

# Separate call: --ttl-ms applies to every key a call sets, and only the
# cache token should expire.
if [ ${#cache_ttl_args[@]} -gt 0 ]; then
  herdr pane report-metadata "$HERDR_PANE_ID" \
    --source "$agent-rows" --agent "$agent" "${cache_ttl_args[@]}" >/dev/null 2>&1 || true
fi

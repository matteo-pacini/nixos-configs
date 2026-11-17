# Claude Code statusLine command on hosts whose desktop shell shows the plan
# limit (custom.herdr.workbench.claudeLimitsFile). Records the input's
# rate_limits in $XDG_RUNTIME_DIR/desk/claude-limits.json, then renders the
# status line with claude-statusline from the same input.
#
# The file is one JSON line:
#   {"written_at":<epoch s>,"seven_day":{"used_percentage":N,"resets_at":N}|null,"five_hour":…}
# Every session on the host writes the same file, each with the reading its
# own session last received, so idle sessions carry older, lower values. Each
# window is therefore merged with the file's: a window missing from the input
# keeps the file's; a later resets_at wins (a new window, even if lower); the
# same resets_at keeps the higher used_percentage (usage only grows within a
# window); an earlier resets_at is ignored.
#
# It is written only when the input has at least one usable window, and then
# only when the merged windows differ from the file's (or the file is missing
# or not a valid file), or, as a liveness refresh, when written_at is 900 s
# old or in the future and the input carries a window whose resets_at is the
# merged one's. So written_at is the last time a running session reported the
# current window, and identical or lower readings write nothing. It is never
# deleted or emptied. Read-merge-write is not locked: a lower value written
# over a higher one lasts until the next call of a session holding the higher.
input=$(cat)

record() {
  [ -n "${XDG_RUNTIME_DIR:-}" ] || return 0
  local dir="$XDG_RUNTIME_DIR/desk"
  local file="$dir/claude-limits.json"
  local now old line tmp
  now=$(date +%s) || return 0
  old=$(cat "$file" 2>/dev/null) || old=""

  # Prints the line to write, or nothing (see the header for when).
  line=$(printf '%s' "$input" | jq -c --argjson now "$now" --arg old "$old" '
    def win: if type == "object" and (.used_percentage | type) == "number"
                and (.resets_at | type) == "number"
             then {used_percentage, resets_at} else null end;
    def merge($i; $f):
      if $i == null then $f
      elif $f == null then $i
      elif $i.resets_at > $f.resets_at then $i
      elif $i.resets_at == $f.resets_at then
        (if $i.used_percentage > $f.used_percentage then $i else $f end)
      else $f end;
    def windows: {seven_day: (.seven_day | win), five_hour: (.five_hour | win)};
    def current($i; $m): $i != null and $i.resets_at == $m.resets_at;
    (.rate_limits | if type == "object" then . else {} end | windows) as $w
    | if $w.seven_day == null and $w.five_hour == null then empty else
        (try ($old | fromjson) catch null) as $o
        | (($o | type) == "object" and ($o.written_at | type) == "number") as $valid
        | (if $valid then $o | windows else {} end) as $f
        | {seven_day: merge($w.seven_day; $f.seven_day),
           five_hour: merge($w.five_hour; $f.five_hour)} as $m
        | if ($valid | not) or $o.seven_day != $m.seven_day
             or $o.five_hour != $m.five_hour
             or ((($now - $o.written_at) >= 900 or ($now - $o.written_at) < 0)
                 and (current($w.seven_day; $m.seven_day)
                      or current($w.five_hour; $m.five_hour)))
          then {written_at: $now} + $m
          else empty end
      end') || return 0
  [ -n "$line" ] || return 0

  # Another session may create it between the test and mkdir.
  [ -d "$dir" ] || mkdir -m 0700 "$dir" || [ -d "$dir" ] || return 0
  tmp=$(mktemp "$dir/.claude-limits.XXXXXX") || return 0
  if ! { printf '%s\n' "$line" >"$tmp" && mv -f "$tmp" "$file"; }; then
    rm -f "$tmp"
  fi
}

# Runs with errexit off (an `||` list), hence the explicit returns above.
record >/dev/null 2>&1 || true

printf '%s' "$input" | claude-statusline

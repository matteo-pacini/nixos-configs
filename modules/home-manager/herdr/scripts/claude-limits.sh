# Claude Code statusLine command on hosts whose desktop shell shows the plan
# limit (custom.herdr.workbench.claudeLimitsFile). Records the input's
# rate_limits in $XDG_RUNTIME_DIR/desk/claude-limits.json, then renders the
# status line with claude-statusline from the same input.
#
# The file is one JSON line:
#   {"written_at":<epoch s>,"seven_day":{"used_percentage":N,"resets_at":N}|null,"five_hour":…}
# It is written only when the input has at least one usable window, and then
# only when the reading differs from the file's or the file is 300 s old,
# missing or unreadable, so a file watch wakes on a change and at most every
# 5 minutes otherwise. It is never deleted or emptied.
input=$(cat)

record() {
  [ -n "${XDG_RUNTIME_DIR:-}" ] || return 0
  local dir="$XDG_RUNTIME_DIR/desk"
  local file="$dir/claude-limits.json"
  local now old line tmp
  now=$(date +%s) || return 0
  old=$(cat "$file" 2>/dev/null) || old=""

  # Prints the line to write, or nothing when there is no usable window or
  # the file already holds this reading and is younger than 300 s.
  line=$(printf '%s' "$input" | jq -c --argjson now "$now" --arg old "$old" '
    def win: if type == "object" and (.used_percentage | type) == "number"
                and (.resets_at | type) == "number"
             then {used_percentage, resets_at} else null end;
    (.rate_limits | if type == "object" then . else {} end) as $r
    | {seven_day: ($r.seven_day | win), five_hour: ($r.five_hour | win)} as $w
    | if $w.seven_day == null and $w.five_hour == null then empty else
        (try ($old | fromjson) catch null) as $o
        | if ($o | type) == "object" and ($o.written_at | type) == "number"
             and ($now - $o.written_at) >= 0 and ($now - $o.written_at) < 300
             and $o.seven_day == $w.seven_day and $o.five_hour == $w.five_hour
          then empty
          else {written_at: $now} + $w end
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

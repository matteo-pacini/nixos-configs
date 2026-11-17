# Claude Code statusLine command on hosts whose desktop shell shows the plan
# limit (custom.herdr.workbench.claudeLimitsFile). Records the input's
# rate_limits in $XDG_RUNTIME_DIR/desk/claude-limits.json, then renders the
# status line with claude-statusline from the same input.
#
# The file is one JSON line:
#   {"written_at":<epoch s>,"seven_day":<window>|null,"five_hour":<window>|null}
#   window: {"used_percentage":N,"resets_at":N,"evidence_at":N|null,
#            "written_at":N,"kind":"fresh"|"stale"}
# Every session on the host writes the same file, each with the reading its
# own session last received; idle sessions keep reporting what they saw at
# their last API answer. A reading's evidence time is the modification time
# of the session's transcript (transcript_path), written at about that answer;
# only its mtime is taken, the file is never opened. A time in the future
# counts as now; no transcript, or one that cannot be stat'ed, is no evidence,
# older than any. kind is "fresh" when the evidence was at most 60 s old at
# the write.
#
# Each window is merged with the file's: a window missing from the input keeps
# the file's; a later resets_at wins (a new window); an earlier one is
# ignored; the same resets_at goes to the newer evidence, even when lower
# (a limit can be reset within a window). Evidence times at most 60 s apart,
# or both absent, are a tie, and a tie keeps the higher value (the file's
# when equal): two live sessions answering seconds apart report slightly
# different figures, and status lines re-run every 10 s.
#
# It is written only when the input has at least one usable window, and then
# only when the merged windows differ from the file's (or the file is missing,
# not a valid file, or from before evidence_at), or, as a liveness refresh,
# when written_at is 900 s old or in the future and the input carries a window
# whose resets_at is the merged one's. So written_at is the last time a
# running session reported the current window. It is never deleted or
# emptied. Read-merge-write is not locked: two sessions writing at once can
# lose one update, until the loser's next status line.
input=$(cat)

record() {
  [ -n "${XDG_RUNTIME_DIR:-}" ] || return 0
  local dir="$XDG_RUNTIME_DIR/desk"
  local file="$dir/claude-limits.json"
  local now old line tmp transcript evidence
  now=$(date +%s) || return 0
  old=$(cat "$file" 2>/dev/null) || old=""

  transcript=$(printf '%s' "$input" | jq -r '.transcript_path | if type == "string" then . else "" end') || transcript=""
  evidence=null
  if [ -n "$transcript" ]; then
    evidence=$(stat -L -c %Y -- "$transcript" 2>/dev/null) || evidence=null
    case $evidence in '' | *[!0-9]*) evidence=null ;; esac
  fi

  # Prints the line to write, or nothing (see the header for when).
  line=$(printf '%s' "$input" | jq -c --argjson now "$now" --arg old "$old" \
    --argjson ev "$evidence" '
    def num: type == "number";
    def win: if type == "object" and (.used_percentage | num) and (.resets_at | num)
             then {used_percentage, resets_at} else null end;
    # A file window in the current form; one from before evidence_at has none.
    def fwin($w): win as $b | if $b == null then null else $b + {
        evidence_at: (if (.evidence_at | num) then .evidence_at else null end),
        written_at: (if (.written_at | num) then .written_at else $w end),
        kind: (if .kind == "fresh" then "fresh" else "stale" end)} end;
    def clamp: if . == null or . <= $now then . else $now end;
    ($ev | clamp) as $e
    | def iwin: win as $b | if $b == null then null else $b + {
        evidence_at: $e, written_at: $now,
        kind: (if $e != null and $now - $e <= 60 then "fresh" else "stale" end)} end;
    # 1 when evidence $a is newer than $b, -1 when older, 0 for a tie.
    def newer($a; $b):
      if $a == null and $b == null then 0
      elif $b == null then 1 elif $a == null then -1
      elif $a - $b > 60 then 1 elif $b - $a > 60 then -1 else 0 end;
    def merge($i; $f):
      if $i == null then $f
      elif $f == null then $i
      elif $i.resets_at > $f.resets_at then $i
      elif $i.resets_at < $f.resets_at then $f
      else newer($i.evidence_at; $f.evidence_at | clamp) as $n
        | if $n > 0 then $i elif $n < 0 then $f
          elif $i.used_percentage > $f.used_percentage then $i else $f end
      end;
    def current($i; $m): $i != null and $i.resets_at == $m.resets_at;
    (.rate_limits | if type == "object" then . else {} end
      | {seven_day: (.seven_day | iwin), five_hour: (.five_hour | iwin)}) as $w
    | if $w.seven_day == null and $w.five_hour == null then empty else
        (try ($old | fromjson) catch null) as $o
        | (($o | type) == "object" and ($o.written_at | num)) as $valid
        | (if $valid
           then {seven_day: ($o.seven_day | fwin($o.written_at)),
                 five_hour: ($o.five_hour | fwin($o.written_at))}
           else {} end) as $f
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

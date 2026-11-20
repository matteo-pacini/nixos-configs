# herdr-claude-keep-warm: keeps the prompt cache of Claude Code agents from
# expiring while they sit idle, in herdr-core terminals labelled
# agent.keep_warm (the switch in the pane-header mod). Shortly before an
# agent's cache expires it asks a one-word side question with /btw and closes
# the answer: the request reads the conversation's cache, which renews it, and
# nothing joins the conversation or changes the agent's status.
#
# It reads the labels claude-statusline sets (agent.cache_until,
# agent.cache_ttl) and sets two of its own: agent.warm_state=refreshing while
# a refresh runs, and agent.warm_failed=<epoch> once two refreshes in a row
# didn't extend the cache. It then leaves that terminal alone until the cache
# expiry changes (the agent's next turn) or the switch is turned off and on.
# It never turns the switch off.
#
# It types into a terminal a person may be using, so it is careful about
# what stands in the prompt box: see refresh.
#
# Its output is the service's log. A refresh that failed is logged with what
# each look at the screen read and the end of that screen, so the log can hold
# text from the conversation. A terminal that is due but can't take the
# question is logged once per reason, not once per pass.
#
# Runs against this machine's core only; starting it also starts the core.

# hc wraps text sent from inside a herdr terminal in <hc> tags, which would
# make the side question a message to the agent.
unset HC_TERMINAL_ID

# Seconds of cache left at which a refresh runs (lib/warm.js shows the same
# figure), and below which it is too late: a request that arrives after the
# expiry writes the whole context to the cache again.
REFRESH_AT=600
TOO_LATE=30
QUESTION="/btw reply with: ok"

declare -A fails=() failed_until=() seen=() skipped=()
# Set by refresh for check to log: why it returned 1 or 2, and for 1 the end
# of the screen it gave up on.
why='' screen=''
# The no-break space Claude Code draws after its prompt mark.
nbsp=$'\xc2\xa0'

log() { printf '%s %s\n' "$(date +%FT%T%z)" "$*"; }

# The text typed in Claude Code's prompt box on terminal $1's screen, trimmed.
# Fails when the screen doesn't end in a prompt box: a dialog, a picker, shell
# mode or the /btw answer is up.
prompt_text() {
  hc read "$1" 2>/dev/null | awk '
    index($0, "───") == 1 { top = bottom; bottom = NR }
    { line[NR] = $0 }
    END {
      if (!top || index(line[top + 1], "❯") != 1) exit 1
      for (i = top + 1; i < bottom; i++) print line[i]
    }' | sed -e '1s/^❯//' -e "s/$nbsp/ /g" -e 's/^ *//' -e 's/ *$//'
}

# Claude Code's prompt stash (ctrl+s) holds a draft. It holds one: stashing
# another replaces it.
has_stash() { hc read "$1" 2>/dev/null | grep -qE '› stashed *$'; }

# Where the side question's answer stands on terminal $1's screen: closed (no
# answer panel), open (still answering) or answered.
answer() {
  hc read "$1" 2>/dev/null | awk -v question="$QUESTION" '
    { line[NR] = $0 }
    END {
      n = NR
      while (n > 0 && line[n] ~ /^[ \t]*$/) n--
      if (line[n] !~ /Esc to close *$/) { print "closed"; exit }
      for (asked = n; asked > 0; asked--) if (index(line[asked], question)) break
      for (i = asked + 1; i < n; i++) if (index(line[i], "Answering…")) { print "open"; exit }
      print "answered"
    }'
}

cache_until() { hc get "$1" --json 2>/dev/null | jq -r '.labels["agent.cache_until"] // ""'; }

# Refreshes the cache of the agent in terminal $1, which expires at $2.
# Returns 0 when the expiry moved, 1 when it didn't, 2 when the terminal can't
# take the question now.
refresh() {
  local terminal=$1 before=$2 text probe state='' looks='' expires i
  why='' screen=''
  if ! text=$(prompt_text "$terminal"); then
    why="no prompt box on its screen (answer panel: $(answer "$terminal"))"
    return 2
  fi
  if [ -n "$text" ]; then
    # Not while the person may be typing it: only text that stood through
    # the last pass too.
    if [ "${seen[$terminal]:-}" != "$text" ]; then
      seen[$terminal]=$text
      why="text in its prompt box that wasn't there a pass ago"
      return 2
    fi
    # A placeholder or a suggested prompt reads like a typed draft. A typed
    # character replaces those, and joins a draft.
    why="hc keys failed"
    hc keys "$terminal" . >/dev/null || return 2
    sleep 0.5
    probe=$(prompt_text "$terminal") || probe=''
    hc keys "$terminal" backspace >/dev/null || return 2
    if [ "$probe" != . ]; then
      # A draft: set it aside in the stash, which gives it back after the
      # next submit. Not over a draft already stashed.
      if has_stash "$terminal"; then
        why="a draft in its prompt box, and another already stashed"
        return 2
      fi
      hc keys "$terminal" ctrl+s >/dev/null || return 2
      sleep 0.5
      why="the draft in its prompt box didn't stash"
      probe=$(prompt_text "$terminal") || return 2
      # Unchanged: nothing was stashed, so the question would be typed onto
      # the draft and sent with it.
      if [ "$probe" = "$text" ]; then return 2; fi
    fi
  fi

  hc label "$terminal" agent.warm_state=refreshing >/dev/null 2>&1 || true
  why="hc send failed"
  hc send "$terminal" "$QUESTION" >/dev/null || return 1
  for i in $(seq 90); do
    sleep 1
    state=$(answer "$terminal")
    looks+=${state:0:1}
    if [ "$state" = answered ]; then break; fi
    # The panel opens at once when the question was taken as one.
    if [ "$state" = closed ] && [ "$i" -ge 10 ]; then break; fi
  done
  if [ "$state" != answered ]; then
    why="no answer in $i looks, a second apart: $looks (c closed, o open)"
    screen=$(hc read "$terminal" 2>&1 | tail -n 15) || true
  fi
  if [ "$state" != closed ]; then hc keys "$terminal" esc >/dev/null || true; fi
  if [ "$state" != answered ]; then return 1; fi

  # The statusLine sets the new expiry at its next run.
  for i in $(seq 15); do
    sleep 2
    expires=$(cache_until "$terminal")
    if [ -n "$expires" ] && [ "$expires" -gt "$before" ]; then return 0; fi
  done
  why="answered (looks: $looks), but agent.cache_until was still ${expires:-unset} 30 s later"
  return 1
}

forget() {
  if [ "${fails[$1]:-0}" -ge 2 ]; then hc label "$1" agent.warm_failed= >/dev/null 2>&1 || true; fi
  unset "fails[$1]" "failed_until[$1]" "skipped[$1]"
}

check() {
  local terminal=$1 status='' ttl='' expires='' now left rc=0
  IFS="|" read -r status ttl expires < <(
    hc get "$terminal" --json 2>/dev/null |
      jq -r 'select(.state == "live" and .status.app == "claude-code")
        | "\(.status.state // "")|\(.labels["agent.cache_ttl"] // "")|\(.labels["agent.cache_until"] // "")"'
  ) || true
  # A 5-minute cache would need a refresh every 4 minutes, which costs more
  # than one cold start within the hour.
  if [ "$ttl" != 1h ] || [ -z "$expires" ]; then return 0; fi
  if [ -n "${fails[$terminal]:-}" ] && [ "${failed_until[$terminal]}" != "$expires" ]; then forget "$terminal"; fi
  if [ "${fails[$terminal]:-0}" -ge 2 ]; then return 0; fi
  # Typing into a blocked agent would answer its prompt, and a working one
  # keeps its own cache.
  case "$status" in idle | done) ;; *) return 0 ;; esac
  now=$(date +%s)
  left=$((expires - now))
  if [ "$left" -gt "$REFRESH_AT" ] || [ "$left" -le "$TOO_LATE" ]; then return 0; fi

  refresh "$terminal" "$expires" || rc=$?
  if [ "$rc" -ne 2 ]; then
    hc label "$terminal" agent.warm_state= >/dev/null 2>&1 || true
    unset "skipped[$terminal]"
  fi
  case "$rc" in
    0)
      log "refreshed $terminal"
      forget "$terminal"
      ;;
    1)
      fails[$terminal]=$((${fails[$terminal]:-0} + 1))
      failed_until[$terminal]=$expires
      log "refresh of $terminal didn't extend its cache (${fails[$terminal]}): $why"
      if [ -n "$screen" ]; then printf '    | %s\n' "${screen//$'\n'/$'\n'    | }"; fi
      if [ "${fails[$terminal]}" -eq 2 ]; then
        hc label "$terminal" "agent.warm_failed=$now" >/dev/null 2>&1 || true
      fi
      ;;
    2)
      if [ "${skipped[$terminal]:-}" != "$why" ]; then
        skipped[$terminal]=$why
        log "$terminal has $left s of cache left and can't be refreshed: $why"
      fi
      ;;
  esac
}

pass() {
  local terminal kept
  kept=$(hc ls --json --label agent.keep_warm=1 2>/dev/null | jq -r '.terminals[]?.address') || kept=''
  for terminal in "${!fails[@]}"; do
    # Switched off, or gone: turning it on again starts over.
    grep -qxF "$terminal" <<<"$kept" || forget "$terminal"
  done
  for terminal in $kept; do
    case "$terminal" in */*) continue ;; esac # another machine's terminal
    check "$terminal"
  done
}

# A refresh this service was stopped in the middle of.
for terminal in $(hc ls --json --label agent.warm_state=refreshing 2>/dev/null | jq -r '.terminals[]?.address'); do
  case "$terminal" in */*) continue ;; esac
  hc label "$terminal" agent.warm_state= >/dev/null 2>&1 || true
done

while :; do
  pass
  sleep 30
done

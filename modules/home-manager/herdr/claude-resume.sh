# herdr-claude-resume: types `claude --resume <id>` into a herdr-core terminal
# that still carries a claude.session label (set by claude-session) but is
# back at its shell, i.e. Claude died without quitting: a reboot or crash
# recovered the terminal as a shell.
#
# Runs against this machine's core only; starting it also starts the core.

state="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/herdr-claude-resume"
mkdir -p "$state"
# One attempt per terminal and session, kept until reboot: a session that
# crashes on resume is not retried in a loop.
tried="$state/tried"
touch "$tried"

is_shell() {
  case "${1#-}" in
    zsh | bash | sh | fish | nu) return 0 ;;
    *) return 1 ;;
  esac
}

# Prints the session to resume in terminal $1, if any.
candidate() {
  local session='' fg=''
  IFS="|" read -r session fg < <(
    hc get "$1" --json 2>/dev/null |
      jq -r 'select(.state == "live") | "\(.labels["claude.session"] // "")|\(.foreground.name // "")"'
  ) || true
  if [ -n "$session" ] && is_shell "$fg"; then echo "$session"; fi
}

check() {
  local terminal=$1 session
  case "$terminal" in */*) return ;; esac # another machine's terminal
  session=$(candidate "$terminal")
  [ -n "$session" ] || return 0
  grep -qxF "$terminal $session" "$tried" && return 0
  # A deliberate quit clears the label from a SessionEnd hook that can still
  # be running when the shell comes back to the foreground.
  sleep 3
  [ "$(candidate "$terminal")" = "$session" ] || return 0
  echo "$terminal $session" >>"$tried"
  echo "resuming $session in $terminal"
  hc send "$terminal" "claude --resume $session" >/dev/null || true
}

while :; do
  # The event stream ends with the core, and its losses are gone once a new
  # core recovers the terminals, so scan everything on every (re)connect.
  for terminal in $(hc ls --json 2>/dev/null | jq -r '.terminals[]?.address'); do
    check "$terminal"
  done
  hc events --json 2>/dev/null |
    jq --unbuffered -r 'select(.params.type? == "foreground") | .params.terminal' |
    while read -r terminal; do check "$terminal"; done || true
  sleep 5
done

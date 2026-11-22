# Claude Code SessionStart/SessionEnd hook: keeps the claude.session label on
# this herdr-core terminal in step with the running session, for
# herdr-claude-resume.
#
#   claude-session start|end   (hook JSON on stdin)
#
# Only a deliberate quit clears the label, so one left behind marks a session
# to resume. The same quit turns the terminal's keep-cache-warm switch off
# (lib/warm.js): a session started there later must not inherit it. No-op
# outside herdr-core; never fails the hook.

[ -n "${HC_TERMINAL_ID:-}" ] || exit 0
input=$(cat)

case "${1:-}" in
  start)
    session=$(jq -r '.session_id // empty' <<<"$input" || true)
    [ -n "$session" ] && hc label "$HC_TERMINAL_ID" "claude.session=$session"
    ;;
  end)
    case "$(jq -r '.reason // empty' <<<"$input")" in
      # /exit, Ctrl+C twice, /logout.
      prompt_input_exit | logout)
        hc label "$HC_TERMINAL_ID" claude.session= agent.keep_warm= agent.warm_state= agent.warm_failed=
        ;;
      # "other" is a signal (the core stopping at shutdown, a kill): resume
      # it, switch and all. "clear" starts the next session ~40 ms later from
      # a separate hook process, so clearing could land after the new label,
      # and the work in the pane carries on.
      *) ;;
    esac
    ;;
esac >/dev/null 2>&1 || true

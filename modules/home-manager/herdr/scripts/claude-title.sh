# Claude Code SessionStart/UserPromptSubmit hook: gives the session the name
# its herdr-core terminal was renamed to in the workbench (the agent.name
# label, set by agent-list's Rename), so the sidebar, the pane header and
# Claude Code's own session name agree.
#
# The label is a rename Claude Code hasn't taken yet. This hook hands it over
# as the hook's `sessionTitle`, which names the session as /rename does, and
# removes the label: from then on the mods show the terminal's title, which
# Claude Code sets to the session's name. Nothing is typed into the terminal.
#
# A /rename in Claude Code that came after the rename in the workbench wins.
# The hook tells the order from two labels:
#   claude.title     the session's name at this hook's last run, as JSON (""
#                    for a session never named), set here;
#   agent.name_base  the terminal's title when the workbench rename was made,
#                    set with agent.name (lib/name.js).
# The session was renamed in between when its name is neither of them.
#
# Claude Code takes `sessionTitle` from UserPromptSubmit and from a
# SessionStart whose source is startup, resume or fork; on any other event
# the hook only records the name. Prints nothing else, no-op outside
# herdr-core, and never fails the hook: a failure here would block the prompt.

[ -n "${HC_TERMINAL_ID:-}" ] || exit 0
input=$(cat)
terminal=$(hc get "$HC_TERMINAL_ID" --json 2>/dev/null) || exit 0

# The hook's input goes in on stdin, not as an argument: it holds the whole
# prompt, which can be longer than one argument may be.
plan=$(printf '%s\n%s\n' "$input" "$terminal" | jq -sc '
  .[0] as $in | (.[1].labels // {}) as $labels
  | ($in.session_title // "") as $now
  | ($labels["agent.name"] // "") as $name
  | ($labels["agent.name_base"] // "") as $base
  | ($labels["claude.title"] | if . == null then null else (try fromjson catch null) end) as $seen
  | ($in.hook_event_name == "UserPromptSubmit"
      or ($in.hook_event_name == "SessionStart" and ($in.source | IN("startup", "resume", "fork")))) as $takes
  | (if $name == "" or ($takes | not) then "wait"
     elif $name == $now then "drop"
     elif $seen != null and $now != $seen and $now != $base then "drop"
     else "give" end) as $do
  | (if $do == "give" then $name else $now end) as $title
  | { labels: ((if $do == "wait" then [] else ["agent.name=", "agent.name_base="] end)
        + (if ($title | tojson) == $labels["claude.title"] then [] else ["claude.title=" + ($title | tojson)] end))
    , out: (if $do == "give"
        then {hookSpecificOutput: {hookEventName: $in.hook_event_name, sessionTitle: $name}}
        else null end) }' 2>/dev/null) || exit 0

mapfile -t labels < <(jq -r '.labels[]' <<<"$plan")
if [ "${#labels[@]}" -gt 0 ]; then
  hc label "$HC_TERMINAL_ID" "${labels[@]}" >/dev/null 2>&1 || true
fi
jq -c '.out // empty' <<<"$plan"

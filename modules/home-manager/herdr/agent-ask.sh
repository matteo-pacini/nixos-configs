# Claude Code and Codex hook for hosts with the herdr-app agent-list mod.
# Inside a herdr-app terminal, a PermissionRequest sets `agent.ask` (one line:
# the tool and its command, file or question) and `agent.ask_detail` (the
# agent's own description of it); any other event clears both. Trust them
# only while the agent is blocked: denying a Claude prompt fires no hook, so a
# stale label is possible until the next event.
# Prints nothing: both apps read a PermissionRequest hook's stdout as its
# decision, and an empty one leaves the prompt to the person.
input=$(cat)
[ -n "${HC_TERMINAL_ID:-}" ] || exit 0

IFS=$'\037' read -r ask detail <<EOF
$(printf '%s' "$input" | jq -r '
  def line: tostring | split("\n") | map(select(test("\\S"))) | (.[0] // "") | .[0:200];
  .tool_name as $tool | (.tool_input // {}) as $in
  | if .hook_event_name != "PermissionRequest" then ["", ""]
    elif $tool == "AskUserQuestion" then [($in.questions[0].question // "Has a question" | line), ""]
    # Codex sends a patch as its command; the first file it touches says more.
    elif $tool == "apply_patch" then
      ["Edit " + (($in.command // "") | [scan("\\*\\*\\* (?:Add|Update|Delete) File: (.+)")] | (.[0][0] // "files")), ""]
    elif $in.command then ["\($tool): \($in.command | line)", ($in.description // "" | line)]
    elif $in.file_path then ["\($tool): \($in.file_path)", ""]
    elif $in.reason then ["\($tool): \($in.reason | line)", ""]
    else [$tool // "Needs permission", ""] end
  | join("\u001f")')
EOF

# An empty value removes the label.
hc label "$HC_TERMINAL_ID" "agent.ask=$ask" "agent.ask_detail=$detail" >/dev/null 2>&1 || true

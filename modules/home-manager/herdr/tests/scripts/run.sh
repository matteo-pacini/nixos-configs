#!/usr/bin/env bash
# Tests for the hook scripts in ../../scripts, run with errexit, nounset and
# pipefail as writeShellApplication runs them. `hc` is a fake on PATH that
# appends its arguments, one per line, to $HC_LOG.
# Usage: run.sh <scripts dir>   (needs bash, jq, coreutils, grep, sed on PATH)
set -euo pipefail

scripts=$(realpath "$1")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir "$work/bin"
# The bash running this, not /usr/bin/env: the Nix build sandbox has no env.
cat >"$work/bin/hc" <<EOF
#!$BASH
printf '%s\n' "\$@" >>"\$HC_LOG"
EOF
chmod +x "$work/bin/hc"
export PATH="$work/bin:$PATH" HC_LOG="$work/hc.log"

failed=0
check() { # name expected actual
  if [ "$2" == "$3" ]; then
    echo "ok   $1"
  else
    echo "FAIL $1"
    diff <(printf '%s\n' "$2") <(printf '%s\n' "$3") | sed 's/^/     /'
    failed=1
  fi
}
run() { # script, stdin from the caller
  : >"$HC_LOG"
  bash -euo pipefail "$scripts/$1" >"$work/stdout"
  check "$1 prints nothing" "" "$(cat "$work/stdout")"
}

# ---- codex-labels.sh ----
# Rollout lines as Codex 0.166 writes them, cut to the fields the script reads.
cat >"$work/rollout.jsonl" <<'EOF'
{"timestamp":"2026-11-06T10:37:39.669Z","type":"session_meta","payload":{"cli_version":"0.166.0"}}
{"type":"turn_context","payload":{"effort":"medium","model":"gpt-6-astra"}}
{"type":"event_msg","payload":{"type":"token_count","info":{"model_context_window":258400,"last_token_usage":{"total_tokens":20000}}}}
{"type":"turn_context","payload":{"effort":"high","model":"gpt-6-astra"}}
{"type":"event_msg","payload":{"type":"token_count","info":{"model_context_window":258400,"last_token_usage":{"total_tokens":78220}}}}
EOF
hook() { jq -nc --arg t "$1" '{session_id: "s-1", transcript_path: $t, model: "gpt-6-astra", hook_event_name: "Stop"}'; }

HC_TERMINAL_ID=t7 run codex-labels.sh <<<"$(hook "$work/rollout.jsonl")"
# The version comes from the rollout here: this test's parent isn't Codex.
# Context: (78220 - 12000) * 100 / (258400 - 12000) = 26.9 -> 27; the last
# turn's effort and token count win.
check "codex-labels: labels from the last turn" "$(printf '%s\n' label t7 codex.session=s-1 agent.model=gpt-6-astra \
  agent.effort=high agent.version=0.166.0 agent.ctx=27 agent.ctxk=78)" "$(cat "$HC_LOG")"

HC_TERMINAL_ID=t7 run codex-labels.sh <<<"$(hook "$work/missing.jsonl")"
check "codex-labels: no transcript clears what it can't read" "$(printf '%s\n' label t7 codex.session=s-1 agent.model=gpt-6-astra \
  agent.effort= agent.version= agent.ctx= agent.ctxk=)" "$(cat "$HC_LOG")"

(unset HC_TERMINAL_ID; run codex-labels.sh <<<"$(hook "$work/rollout.jsonl")")
check "codex-labels: outside herdr, labels nothing" "" "$(cat "$HC_LOG")"

# ---- agent-ask.sh ----
ask() { # event tool tool_input-json
  : >"$HC_LOG"
  jq -nc --arg e "$1" --arg t "$2" --argjson i "$3" '{hook_event_name: $e, tool_name: $t, tool_input: $i}' |
    HC_TERMINAL_ID=t2 bash -euo pipefail "$scripts/agent-ask.sh"
  sed -n '3,4p' "$HC_LOG"
}
check "agent-ask: a command and its description" "$(printf '%s\n' 'agent.ask=Bash: rm -rf build' 'agent.ask_detail=Clean the build')" \
  "$(ask PermissionRequest Bash '{"command":"rm -rf build\nmore","description":"Clean the build"}')"
check "agent-ask: a question" "$(printf '%s\n' 'agent.ask=Which one?' 'agent.ask_detail=')" \
  "$(ask PermissionRequest AskUserQuestion '{"questions":[{"question":"Which one?"}]}')"
check "agent-ask: a Codex patch names its first file" "$(printf '%s\n' 'agent.ask=Edit src/a.rs' 'agent.ask_detail=')" \
  "$(ask PermissionRequest apply_patch '{"command":"*** Begin Patch\n*** Update File: src/a.rs\n*** Add File: b"}')"
check "agent-ask: a file" "$(printf '%s\n' 'agent.ask=Write: /tmp/x' 'agent.ask_detail=')" \
  "$(ask PermissionRequest Write '{"file_path":"/tmp/x"}')"
check "agent-ask: any other event clears both" "$(printf '%s\n' 'agent.ask=' 'agent.ask_detail=')" \
  "$(ask PostToolUse Bash '{"command":"ls"}')"

# ---- codex-hooks.jq ----
merge() { jq -f "$scripts/codex-hooks.jq"; }
once=$(merge <<<'{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"mine"}]}]}}')
twice=$(merge <<<"$once")
check "codex-hooks: idempotent" "$once" "$twice"
check "codex-hooks: keeps other hooks, adds ours once, last" '["mine","herdr-codex-labels","herdr-agent-ask"]' \
  "$(jq -c '[.hooks.Stop[].hooks[].command]' <<<"$twice")"
check "codex-hooks: a changed definition replaces the old one" '[{"command":"herdr-agent-ask","timeout":3}]' \
  "$(merge <<<'{"hooks":{"Interrupt":[{"hooks":[{"type":"command","command":"herdr-agent-ask","timeout":99}]}]}}' |
    jq -c '[.hooks.Interrupt[].hooks[] | {command, timeout}]')"
check "codex-hooks: from an empty file" "9" "$(merge <<<'{}' | jq '[.hooks[][]] | length')"

exit "$failed"

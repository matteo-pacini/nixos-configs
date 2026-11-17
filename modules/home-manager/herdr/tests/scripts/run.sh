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

# ---- claude-limits.sh ----
# The renderer, npx, is a fake that prefixes its input; claude-statusline runs
# the real script. `date` is a fake printing $FAKE_NOW, on PATH only here.
mkdir "$work/limbin"
cat >"$work/limbin/npx" <<EOF
#!$BASH
printf 'rendered:'
cat
EOF
cat >"$work/limbin/claude-statusline" <<EOF
#!$BASH
exec bash -euo pipefail "$scripts/claude-statusline.sh"
EOF
cat >"$work/limbin/date" <<EOF
#!$BASH
printf '%s\n' "\$FAKE_NOW"
EOF
chmod +x "$work/limbin/"*
export XDG_RUNTIME_DIR="$work/xdg"
mkdir -m 0700 "$XDG_RUNTIME_DIR"
lfile="$XDG_RUNTIME_DIR/desk/claude-limits.json"

# Status-line input carrying `rate_limits` = $1, or none when $1 is empty.
sl() {
  if [ -n "${1:-}" ]; then
    jq -nc --argjson r "$1" '{session_id: "s-9", cwd: "/x", model: {display_name: "Opus"}, rate_limits: $r}'
  else
    jq -nc '{session_id: "s-9", cwd: "/x", model: {display_name: "Opus"}}'
  fi
}
# Runs claude-limits.sh at time $1 with stdin from the caller, outside herdr.
# Stdout and stderr land in $work/lim.out and $work/lim.err; prints the exit code.
lim() {
  local rc=0
  : >"$HC_LOG"
  (unset HC_TERMINAL_ID; PATH="$work/limbin:$PATH" FAKE_NOW=$1 \
    bash -euo pipefail "$scripts/claude-limits.sh" >"$work/lim.out" 2>"$work/lim.err") || rc=$?
  echo "$rc"
}
# Extra fields and windows are invented, to show only the contract's reach the file.
both='{"five_hour":{"used_percentage":12.5,"resets_at":1794920000,"extra":1},"seven_day":{"used_percentage":34.25,"resets_at":1795078800},"seven_day_x":{"used_percentage":1,"resets_at":2}}'
week='{"seven_day":{"used_percentage":34,"resets_at":1795078800}}'

check "claude-limits: no file from no rate_limits" "0 absent" "$(lim 1000 <<<"$(sl)") $([ -e "$lfile" ] && echo present || echo absent)"
check "claude-limits: no file from empty rate_limits" "0 absent" "$(lim 1000 <<<"$(sl '{}')") $([ -e "$lfile" ] && echo present || echo absent)"

check "claude-limits: both windows, fractional" "0" "$(lim 1000 <<<"$(sl "$both")")"
check "claude-limits: both windows, the file" \
  '{"written_at":1000,"seven_day":{"used_percentage":34.25,"resets_at":1795078800},"five_hour":{"used_percentage":12.5,"resets_at":1794920000}}' \
  "$(cat "$lfile")"
check "claude-limits: one line ending in a newline" "1" "$(wc -l <"$lfile")"
check "claude-limits: directory is 0700" "700" "$(stat -c %a "$XDG_RUNTIME_DIR/desk")"
check "claude-limits: no temporary file left" "claude-limits.json" "$(command ls -A "$XDG_RUNTIME_DIR/desk")"
check "claude-limits: outside herdr, labels nothing" "" "$(cat "$HC_LOG")"
check "claude-limits: writer prints nothing on stderr" "" "$(cat "$work/lim.err")"

rm "$lfile"
lim 1100 <<<"$(sl "$week")" >/dev/null
check "claude-limits: only seven_day, written at once" \
  '{"written_at":1100,"seven_day":{"used_percentage":34,"resets_at":1795078800},"five_hour":null}' "$(cat "$lfile")"

# The merge. A file the writer leaves alone keeps its inode and the mtime
# `put` and `step` give it (epoch 100); a write replaces both.
R=1795078800 R2=$((1795078800 + 604800)) R0=$((1795078800 - 604800)) F=1794920000
w() { printf '{"used_percentage":%s,"resets_at":%s}' "$1" "$2"; }
in7() { printf '{"seven_day":%s}' "$(w "$1" "$2")"; }
in5() { printf '{"five_hour":%s}' "$(w "$1" "$2")"; }
in75() { printf '{"seven_day":%s,"five_hour":%s}' "$(w "$1" "$2")" "$(w "$3" "$4")"; }
fl() { printf '{"written_at":%s,"seven_day":%s,"five_hour":%s}' "$1" "$2" "$3"; }
put() {
  printf '%s' "$1" >"$lfile"
  touch -d @100 "$lfile"
}
# Runs the writer at time $1 with rate_limits $2; prints written or untouched.
step() {
  local was=absent
  if [ -e "$lfile" ]; then was=$(stat -c %i "$lfile"); fi
  lim "$1" <<<"$(sl "$2")" >/dev/null
  if [ -e "$lfile" ] && [ "$(stat -c '%i %Y' "$lfile")" = "$was 100" ]; then echo untouched; else echo written; fi
  if [ -e "$lfile" ]; then touch -d @100 "$lfile"; fi
}

put "$(fl 2000 "$(w 50 $R)" null)"
check "claude-limits: same resets_at, lower, untouched" "untouched" "$(step 2010 "$(in7 40 $R)")"
check "claude-limits: same resets_at, higher, written" "written $(fl 2020 "$(w 55 $R)" null)" \
  "$(step 2020 "$(in7 55 $R)") $(cat "$lfile")"
check "claude-limits: later resets_at, lower, accepted" "written $(fl 2030 "$(w 5 $R2)" null)" \
  "$(step 2030 "$(in7 5 $R2)") $(cat "$lfile")"
check "claude-limits: earlier resets_at, higher, ignored" "untouched" "$(step 2040 "$(in7 99 $R)")"
check "claude-limits: earlier resets_at at 900 s, not refreshed" "untouched $(fl 2030 "$(w 5 $R2)" null)" \
  "$(step 2930 "$(in7 99 $R)") $(cat "$lfile")"

put "$(fl 3000 "$(w 30 $R)" "$(w 10 $F)")"
check "claude-limits: five_hour absent from the input keeps the file's" \
  "written $(fl 3010 "$(w 31 $R)" "$(w 10 $F)")" "$(step 3010 "$(in7 31 $R)") $(cat "$lfile")"
check "claude-limits: seven_day absent from the input keeps the file's" \
  "written $(fl 3020 "$(w 31 $R)" "$(w 12 $F)")" "$(step 3020 "$(in5 12 $F)") $(cat "$lfile")"
check "claude-limits: present window lower, absent one kept, untouched" "untouched" "$(step 3030 "$(in5 11 $F)")"
check "claude-limits: windows merge independently in one call" \
  "written $(fl 3040 "$(w 35 $R)" "$(w 12 $F)")" "$(step 3040 "$(in75 35 $R 8 $F)") $(cat "$lfile")"
check "claude-limits: only five_hour, lower, at 900 s, refreshed" \
  "written $(fl 3940 "$(w 35 $R)" "$(w 12 $F)")" "$(step 3940 "$(in5 8 $F)") $(cat "$lfile")"

rm "$lfile"
check "claude-limits: 77, 80, 78, 73 writes twice" "written written untouched untouched" \
  "$(step 4000 "$(in7 77 $R)") $(step 4010 "$(in7 80 $R)") $(step 4020 "$(in7 78 $R)") $(step 4030 "$(in7 73 $R)")"
check "claude-limits: 77, 80, 78, 73 ends at 80" "$(fl 4010 "$(w 80 $R)" null)" "$(cat "$lfile")"
check "claude-limits: identical reading 1 s and 899 s later, untouched" "untouched untouched" \
  "$(step 4011 "$(in7 80 $R)") $(step 4909 "$(in7 80 $R)")"
check "claude-limits: identical reading at 900 s, refreshed" "written $(fl 4910 "$(w 80 $R)" null)" \
  "$(step 4910 "$(in7 80 $R)") $(cat "$lfile")"
check "claude-limits: lower reading at 900 s, refreshed at the max" "written $(fl 5810 "$(w 80 $R)" null)" \
  "$(step 5810 "$(in7 73 $R)") $(cat "$lfile")"
check "claude-limits: only an earlier resets_at at 900 s, not refreshed" "untouched" \
  "$(step 6710 "$(in7 90 $R0)")"

put "$(fl 6800 "$(w 78 $R)" null)"
check "claude-limits: a lost update is repaired" "written $(fl 6810 "$(w 80 $R)" null)" \
  "$(step 6810 "$(in7 80 $R)") $(cat "$lfile")"

for old in missing '' garbage '[1,2]' "$(fl 7000 '{"used_percentage":"90","resets_at":"1795078800"}' null)" \
  '{"seven_day":{"used_percentage":34,"resets_at":1795078800},"five_hour":null}'; do
  if [ "$old" = missing ]; then rm -f "$lfile"; else put "$old"; fi
  check "claude-limits: file ${old:-empty}, written from the input" "written $(fl 7010 "$(w 34 $R)" null)" \
    "$(step 7010 "$(in7 34 $R)") $(cat "$lfile")"
done

put "$(fl 99999 "$(w 80 $R)" null)"
check "claude-limits: written_at in the future, refreshed" "written $(fl 8000 "$(w 80 $R)" null)" \
  "$(step 8000 "$(in7 80 $R)") $(cat "$lfile")"

cp "$lfile" "$work/lim.before"
for input in "$(sl)" "$(sl '{}')" "$(sl '{"seven_day":{"used_percentage":"34","resets_at":1795078800}}')" \
  "$(sl '{"seven_day":{"used_percentage":34,"resets_at":null}}')"; do
  lim 5000 <<<"$input" >/dev/null
  check "claude-limits: no usable window leaves the file as it is: $(jq -c '.rate_limits' <<<"$input")" \
    "same" "$(cmp -s "$lfile" "$work/lim.before" && echo same || echo differs)"
done

printf '{"written_at":' >"$lfile"
lim 1500 <<<"$(sl "$week")" >/dev/null
check "claude-limits: a corrupt file is replaced" \
  '{"written_at":1500,"seven_day":{"used_percentage":34,"resets_at":1795078800},"five_hour":null}' "$(cat "$lfile")"

expected=$(sl "$both" | PATH="$work/limbin:$PATH" bash -euo pipefail "$scripts/claude-statusline.sh")
check "claude-limits: the renderer's stub is reached" "rendered:$(sl "$both")" "$expected"
lim 1600 <<<"$(sl "$both")" >/dev/null
check "claude-limits: status line output unchanged" "$expected" "$(cat "$work/lim.out")"

check "claude-limits: XDG_RUNTIME_DIR unset, exit and output" "0 $expected" \
  "$(unset XDG_RUNTIME_DIR; printf '%s ' "$(lim 1700 <<<"$(sl "$both")")"; cat "$work/lim.out")"
check "claude-limits: XDG_RUNTIME_DIR unset, nothing on stderr" "" "$(cat "$work/lim.err")"

for case in locked lockeddesk; do
  rm -rf "$work/xdg-$case"
  mkdir -p "$work/xdg-$case"
  if [ "$case" = lockeddesk ]; then mkdir -m 0500 "$work/xdg-$case/desk"; fi
  chmod 0500 "$work/xdg-$case"
  check "claude-limits: unwritable $case, exit and output" "0 $expected" \
    "$(XDG_RUNTIME_DIR="$work/xdg-$case"; printf '%s ' "$(lim 1800 <<<"$(sl "$both")")"; cat "$work/lim.out")"
  check "claude-limits: unwritable $case, nothing on stderr" "" "$(cat "$work/lim.err")"
  check "claude-limits: unwritable $case, no file" "absent" \
    "$([ -e "$work/xdg-$case/desk/claude-limits.json" ] && echo present || echo absent)"
  chmod -R u+w "$work/xdg-$case"
done

: >"$HC_LOG"
rm "$lfile"
sl "$both" | HC_TERMINAL_ID=t3 PATH="$work/limbin:$PATH" FAKE_NOW=1900 \
  bash -euo pipefail "$scripts/claude-limits.sh" >/dev/null
check "claude-limits: inside herdr, labels still set" "label t3" "$(head -n 2 "$HC_LOG" | paste -sd ' ')"
check "claude-limits: inside herdr, the file too" "1900" "$(jq .written_at "$lfile")"

exit "$failed"

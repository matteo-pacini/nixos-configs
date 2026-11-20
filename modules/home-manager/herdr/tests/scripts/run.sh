#!/usr/bin/env bash
# Tests for the hook scripts in ../../scripts, run with errexit, nounset and
# pipefail as writeShellApplication runs them. `hc` is a fake on PATH that
# appends its arguments, one per line, to $HC_LOG.
# Usage: run.sh <scripts dir>   (needs bash, jq, coreutils, grep, sed, awk on PATH)
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
# The commands as agent-labels.nix passes them, in an invented profile.
L=/etc/profiles/per-user/ada/bin/herdr-codex-labels A=/etc/profiles/per-user/ada/bin/herdr-agent-ask
merge() { jq -f "$scripts/codex-hooks.jq" --arg labels "${1:-$L}" --arg ask "${2:-$A}"; }
stop() { jq -c '[.hooks.Stop[].hooks[].command]'; }
mine='{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"mine"}]}]}}'
once=$(merge <<<"$mine")
twice=$(merge <<<"$once")
check "codex-hooks: idempotent" "$once" "$twice"
check "codex-hooks: keeps other hooks, adds ours once, last" "[\"mine\",\"$L\",\"$A\"]" "$(stop <<<"$twice")"
check "codex-hooks: a changed definition replaces the old one" "[{\"command\":\"$A\",\"timeout\":3}]" \
  "$(merge <<<'{"hooks":{"Interrupt":[{"hooks":[{"type":"command","command":"herdr-agent-ask","timeout":99}]}]}}' |
    jq -c '[.hooks.Interrupt[].hooks[] | {command, timeout}]')"
check "codex-hooks: from an empty file" "9" "$(merge <<<'{}' | jq '[.hooks[][]] | length')"
bare=$(merge herdr-codex-labels herdr-agent-ask <<<"$mine")
check "codex-hooks: bare names, as written before, are in every event" "9" \
  "$(jq '[.hooks[][].hooks[].command | select(. == "herdr-codex-labels" or . == "herdr-agent-ask")] | length' <<<"$bare")"
check "codex-hooks: bare names give way to the absolute commands, once each, last" "$once" "$(merge <<<"$bare")"
check "codex-hooks: another directory's copy of ours is replaced" "[\"$L\",\"$A\"]" \
  "$(merge <<<'{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"/usr/local/bin/herdr-codex-labels"}]},{"hooks":[{"type":"command","command":"/old/bin/herdr-agent-ask","timeout":3}]}]}}' | stop)"
logger='{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"my-herdr-agent-ask-logger"},{"type":"command","command":"/opt/bin/herdr-codex-labels-audit"}]}]}}'
check "codex-hooks: a foreign command containing our name is kept" \
  "[\"my-herdr-agent-ask-logger\",\"/opt/bin/herdr-codex-labels-audit\",\"$L\",\"$A\"]" "$(merge <<<"$logger" | stop)"
check "codex-hooks: idempotent with foreign commands containing our name" "$(merge <<<"$logger")" \
  "$(merge <<<"$logger" | merge | merge)"

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

# Status-line input carrying `rate_limits` = $1, or none when $1 is empty, and
# `transcript_path` = $2 when given.
sl() {
  local o
  if [ -n "${1:-}" ]; then
    o=$(jq -nc --argjson r "$1" '{session_id: "s-9", cwd: "/x", model: {display_name: "Opus"}, rate_limits: $r}')
  else
    o=$(jq -nc '{session_id: "s-9", cwd: "/x", model: {display_name: "Opus"}}')
  fi
  if [ -n "${2:-}" ]; then o=$(jq -c --arg t "$2" '. + {transcript_path: $t}' <<<"$o"); fi
  printf '%s\n' "$o"
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
  '{"written_at":1000,"seven_day":{"used_percentage":34.25,"resets_at":1795078800,"evidence_at":null,"written_at":1000,"kind":"stale"},"five_hour":{"used_percentage":12.5,"resets_at":1794920000,"evidence_at":null,"written_at":1000,"kind":"stale"}}' \
  "$(cat "$lfile")"
check "claude-limits: one line ending in a newline" "1" "$(wc -l <"$lfile")"
check "claude-limits: directory is 0700" "700" "$(stat -c %a "$XDG_RUNTIME_DIR/desk")"
check "claude-limits: no temporary file left" "claude-limits.json" "$(command ls -A "$XDG_RUNTIME_DIR/desk")"
check "claude-limits: outside herdr, labels nothing" "" "$(cat "$HC_LOG")"
check "claude-limits: writer prints nothing on stderr" "" "$(cat "$work/lim.err")"

rm "$lfile"
lim 1100 <<<"$(sl "$week")" >/dev/null
check "claude-limits: only seven_day, written at once" \
  '{"written_at":1100,"seven_day":{"used_percentage":34,"resets_at":1795078800,"evidence_at":null,"written_at":1100,"kind":"stale"},"five_hour":null}' "$(cat "$lfile")"

# The merge. A file the writer leaves alone keeps its inode and the mtime
# `put` and `step` give it (epoch 100); a write replaces both.
R=1795078800 R2=$((1795078800 + 604800)) R0=$((1795078800 - 604800)) F=1794920000
# An input window; a file window as written (value, resets_at, evidence_at,
# written_at, kind); one with no evidence, as an input without a transcript
# writes it.
w() { printf '{"used_percentage":%s,"resets_at":%s}' "$1" "$2"; }
fw() { printf '{"used_percentage":%s,"resets_at":%s,"evidence_at":%s,"written_at":%s,"kind":"%s"}' "$@"; }
ns() { fw "$1" "$2" null "$3" stale; }
in7() { printf '{"seven_day":%s}' "$(w "$1" "$2")"; }
in5() { printf '{"five_hour":%s}' "$(w "$1" "$2")"; }
in75() { printf '{"seven_day":%s,"five_hour":%s}' "$(w "$1" "$2")" "$(w "$3" "$4")"; }
fl() { printf '{"written_at":%s,"seven_day":%s,"five_hour":%s}' "$1" "$2" "$3"; }
put() {
  printf '%s' "$1" >"$lfile"
  touch -d @100 "$lfile"
}
# Runs the writer at time $1 with rate_limits $2 and transcript $3 if given;
# prints written or untouched.
step() {
  local was=absent
  if [ -e "$lfile" ]; then was=$(stat -c %i "$lfile"); fi
  lim "$1" <<<"$(sl "$2" "${3:-}")" >/dev/null
  if [ -e "$lfile" ] && [ "$(stat -c '%i %Y' "$lfile")" = "$was 100" ]; then echo untouched; else echo written; fi
  if [ -e "$lfile" ]; then touch -d @100 "$lfile"; fi
}

put "$(fl 2000 "$(ns 50 $R 2000)" null)"
check "claude-limits: same resets_at, lower, untouched" "untouched" "$(step 2010 "$(in7 40 $R)")"
check "claude-limits: same resets_at, higher, written" "written $(fl 2020 "$(ns 55 $R 2020)" null)" \
  "$(step 2020 "$(in7 55 $R)") $(cat "$lfile")"
check "claude-limits: later resets_at, lower, accepted" "written $(fl 2030 "$(ns 5 $R2 2030)" null)" \
  "$(step 2030 "$(in7 5 $R2)") $(cat "$lfile")"
check "claude-limits: earlier resets_at, higher, ignored" "untouched" "$(step 2040 "$(in7 99 $R)")"
check "claude-limits: earlier resets_at at 900 s, not refreshed" "untouched $(fl 2030 "$(ns 5 $R2 2030)" null)" \
  "$(step 2930 "$(in7 99 $R)") $(cat "$lfile")"

put "$(fl 3000 "$(ns 30 $R 3000)" "$(ns 10 $F 3000)")"
check "claude-limits: five_hour absent from the input keeps the file's" \
  "written $(fl 3010 "$(ns 31 $R 3010)" "$(ns 10 $F 3000)")" "$(step 3010 "$(in7 31 $R)") $(cat "$lfile")"
check "claude-limits: seven_day absent from the input keeps the file's" \
  "written $(fl 3020 "$(ns 31 $R 3010)" "$(ns 12 $F 3020)")" "$(step 3020 "$(in5 12 $F)") $(cat "$lfile")"
check "claude-limits: present window lower, absent one kept, untouched" "untouched" "$(step 3030 "$(in5 11 $F)")"
check "claude-limits: windows merge independently in one call" \
  "written $(fl 3040 "$(ns 35 $R 3040)" "$(ns 12 $F 3020)")" "$(step 3040 "$(in75 35 $R 8 $F)") $(cat "$lfile")"
check "claude-limits: only five_hour, lower, at 900 s, refreshed" \
  "written $(fl 3940 "$(ns 35 $R 3040)" "$(ns 12 $F 3020)")" "$(step 3940 "$(in5 8 $F)") $(cat "$lfile")"

rm "$lfile"
check "claude-limits: 77, 80, 78, 73 writes twice" "written written untouched untouched" \
  "$(step 4000 "$(in7 77 $R)") $(step 4010 "$(in7 80 $R)") $(step 4020 "$(in7 78 $R)") $(step 4030 "$(in7 73 $R)")"
check "claude-limits: 77, 80, 78, 73 ends at 80" "$(fl 4010 "$(ns 80 $R 4010)" null)" "$(cat "$lfile")"
check "claude-limits: identical reading 1 s and 899 s later, untouched" "untouched untouched" \
  "$(step 4011 "$(in7 80 $R)") $(step 4909 "$(in7 80 $R)")"
check "claude-limits: identical reading at 900 s, refreshed" "written $(fl 4910 "$(ns 80 $R 4010)" null)" \
  "$(step 4910 "$(in7 80 $R)") $(cat "$lfile")"
check "claude-limits: lower reading at 900 s, refreshed at the max" "written $(fl 5810 "$(ns 80 $R 4010)" null)" \
  "$(step 5810 "$(in7 73 $R)") $(cat "$lfile")"
check "claude-limits: only an earlier resets_at at 900 s, not refreshed" "untouched" \
  "$(step 6710 "$(in7 90 $R0)")"

put "$(fl 6800 "$(ns 78 $R 6800)" null)"
check "claude-limits: a lost update is repaired" "written $(fl 6810 "$(ns 80 $R 6810)" null)" \
  "$(step 6810 "$(in7 80 $R)") $(cat "$lfile")"

for old in missing '' garbage '[1,2]' "$(fl 7000 '{"used_percentage":"90","resets_at":"1795078800"}' null)" \
  '{"seven_day":{"used_percentage":34,"resets_at":1795078800},"five_hour":null}'; do
  if [ "$old" = missing ]; then rm -f "$lfile"; else put "$old"; fi
  check "claude-limits: file ${old:-empty}, written from the input" "written $(fl 7010 "$(ns 34 $R 7010)" null)" \
    "$(step 7010 "$(in7 34 $R)") $(cat "$lfile")"
done

put "$(fl 99999 "$(ns 80 $R 7990)" null)"
check "claude-limits: written_at in the future, refreshed" "written $(fl 8000 "$(ns 80 $R 7990)" null)" \
  "$(step 8000 "$(in7 80 $R)") $(cat "$lfile")"

# ---- newest evidence wins (the transcript's mtime) ----
# Transcripts with mtime $2, mode 000: the build runs unprivileged, so the
# writer cannot read them, and every case below still takes their mtime.
ts() { : >"$work/$1.jsonl"; touch -d "@$2" "$work/$1.jsonl"; chmod 000 "$work/$1.jsonl"; printf '%s' "$work/$1.jsonl"; }

# 1. The incident: 88 from old evidence; a fresh 42 in the same window wins.
put "$(fl 9000 "$(fw 88 $R 1000 9000 stale)" null)"
check "claude-limits: 1. a fresh 42 beats 88 from older evidence" "written $(fl 10000 "$(fw 42 $R 9990 10000 fresh)" null)" \
  "$(step 10000 "$(in7 42 $R)" "$(ts live 9990)") $(cat "$lfile")"
# 2. Idle sessions still reporting 88 from hours-old transcripts.
check "claude-limits: 2. idle 88s from older transcripts leave 42" "untouched untouched untouched" \
  "$(step 10010 "$(in7 88 $R)" "$(ts idle1 1000)") $(step 10020 "$(in7 88 $R)" "$(ts idle2 2000)") $(step 10030 "$(in7 88 $R)" "$(ts idle3 9900)")"
# An idle session with no transcript at all: no evidence, older than any.
check "claude-limits: 2. an 88 with no evidence leaves 42" "untouched" "$(step 10040 "$(in7 88 $R)")"
check "claude-limits: 2. a missing transcript is no evidence" "untouched" "$(step 10050 "$(in7 88 $R)" "$work/gone.jsonl")"
# 3. Normal growth.
put "$(fl 11000 "$(fw 77 $R 10990 11000 fresh)" null)"
check "claude-limits: 3. a fresh 80 after 77" "written $(fl 11100 "$(fw 80 $R 11095 11100 fresh)" null)" \
  "$(step 11100 "$(in7 80 $R)" "$(ts grow 11095)") $(cat "$lfile")"
# 4. Two live sessions seconds apart: a tie, the higher stays, either order.
rm "$lfile"
step 12001 "$(in7 80 $R)" "$(ts a1 12000)" >/dev/null
step 12006 "$(in7 79 $R)" "$(ts b1 12005)" >/dev/null
check "claude-limits: 4. 80 then 79 seconds later: 80" "80" "$(jq .seven_day.used_percentage "$lfile")"
rm "$lfile"
step 12001 "$(in7 79 $R)" "$(ts a2 12000)" >/dev/null
step 12006 "$(in7 80 $R)" "$(ts b2 12005)" >/dev/null
check "claude-limits: 4. 79 then 80 seconds later: 80" "80" "$(jq .seven_day.used_percentage "$lfile")"
# 5. Nobody has evidence: the highest, as before.
rm "$lfile"
step 13000 "$(in7 50 $R)" >/dev/null
step 13010 "$(in7 60 $R)" >/dev/null
step 13020 "$(in7 55 $R)" >/dev/null
check "claude-limits: 5. no evidence anywhere: the highest" "60" "$(jq .seven_day.used_percentage "$lfile")"
# 6. Idle sessions only: the newest evidence, within 60 s the higher.
rm "$lfile"
step 40000 "$(in7 70 $R)" "$(ts i1 30000)" >/dev/null
check "claude-limits: 6. newer evidence wins though lower" "written $(fl 40010 "$(fw 65 $R 35000 40010 stale)" null)" \
  "$(step 40010 "$(in7 65 $R)" "$(ts i2 35000)") $(cat "$lfile")"
check "claude-limits: 6. within 60 s, the higher" "written 68" \
  "$(step 40020 "$(in7 68 $R)" "$(ts i3 35050)") $(jq .seven_day.used_percentage "$lfile")"
check "claude-limits: 6. within 60 s, a lower one is ignored" "untouched" "$(step 40030 "$(in7 60 $R)" "$(ts i4 35040)")"
check "claude-limits: 6. the oldest again is ignored" "untouched" "$(step 40040 "$(in7 70 $R)" "$work/i1.jsonl")"
# 7. A transcript dated in the future counts as now, and is overtaken.
rm "$lfile"
check "claude-limits: 7. a future mtime is clamped to now" "$(fl 50000 "$(fw 30 $R 50000 50000 fresh)" null)" \
  "$(step 50000 "$(in7 30 $R)" "$(ts future 99999)" >/dev/null; cat "$lfile")"
check "claude-limits: 7. and loses to later evidence" "written 20" \
  "$(step 50200 "$(in7 20 $R)" "$(ts after 50150)") $(jq .seven_day.used_percentage "$lfile")"
# 8. Windows: a later resets_at beats any evidence; an earlier one is
# ignored even when fresh; an absent window keeps the file's.
put "$(fl 60000 "$(fw 40 $R 59990 60000 fresh)" "$(fw 10 $F 59990 60000 fresh)")"
check "claude-limits: 8. a later resets_at with no evidence wins" "written $(fl 60010 "$(ns 3 $R2 60010)" "$(fw 10 $F 59990 60000 fresh)")" \
  "$(step 60010 "$(in7 3 $R2)") $(cat "$lfile")"
check "claude-limits: 8. an earlier resets_at, fresh, is ignored" "untouched" "$(step 60020 "$(in7 90 $R)" "$(ts early 60019)")"
# resets_at within 60 s is the same window, against a file holding 50
# (evidence D) in the week ending R and 10 (evidence D) in the five hours
# ending F.
D=70000
f50=$(fl $D "$(fw 50 $R $D $D fresh)" "$(fw 10 $F $D $D fresh)")
put "$f50"
check "claude-limits: resets_at 1 s earlier, newer evidence wins though lower" \
  "written $(fl $((D + 610)) "$(fw 40 $((R - 1)) $((D + 600)) $((D + 610)) fresh)" "$(fw 10 $F $D $D fresh)")" \
  "$(step $((D + 610)) "$(in7 40 $((R - 1)))" "$(ts d1 $((D + 600)))") $(cat "$lfile")"
put "$f50"
check "claude-limits: resets_at 1 s later, newer evidence wins though lower" \
  "written $(fl $((D + 610)) "$(fw 40 $((R + 1)) $((D + 600)) $((D + 610)) fresh)" "$(fw 10 $F $D $D fresh)")" \
  "$(step $((D + 610)) "$(in7 40 $((R + 1)))" "$(ts d2 $((D + 600)))") $(cat "$lfile")"
put "$f50"
check "claude-limits: resets_at 1 s later, older evidence, higher, untouched" "untouched" \
  "$(step $((D + 40)) "$(in7 90 $((R + 1)))" "$(ts d10 $((D - 600)))")"
put "$f50"
check "claude-limits: resets_at 1 s earlier, within 60 s, higher wins" \
  "written $(fl $((D + 40)) "$(fw 55 $((R - 1)) $((D + 30)) $((D + 40)) fresh)" "$(fw 10 $F $D $D fresh)")" \
  "$(step $((D + 40)) "$(in7 55 $((R - 1)))" "$(ts d3 $((D + 30)))") $(cat "$lfile")"
put "$f50"
check "claude-limits: resets_at 1 s earlier, within 60 s, lower, untouched" "untouched" \
  "$(step $((D + 40)) "$(in7 45 $((R - 1)))" "$(ts d4 $((D + 30)))")"
put "$f50"
check "claude-limits: resets_at 1 s earlier, within 60 s, equal, untouched" "untouched" \
  "$(step $((D + 40)) "$(in7 50 $((R - 1)))" "$(ts d5 $((D + 30)))")"
put "$f50"
check "claude-limits: resets_at 60 s earlier is the same window" \
  "written $(fl $((D + 610)) "$(fw 40 $((R - 60)) $((D + 600)) $((D + 610)) fresh)" "$(fw 10 $F $D $D fresh)")" \
  "$(step $((D + 610)) "$(in7 40 $((R - 60)))" "$(ts d6 $((D + 600)))") $(cat "$lfile")"
put "$f50"
check "claude-limits: resets_at 61 s earlier, untouched" "untouched" \
  "$(step $((D + 610)) "$(in7 40 $((R - 61)))" "$(ts d7 $((D + 600)))")"
put "$f50"
check "claude-limits: resets_at 61 s later wins though lower and older" \
  "written $(fl $((D + 40)) "$(fw 3 $((R + 61)) $((D - 600)) $((D + 40)) stale)" "$(fw 10 $F $D $D fresh)")" \
  "$(step $((D + 40)) "$(in7 3 $((R + 61)))" "$(ts d8 $((D - 600)))") $(cat "$lfile")"
put "$(fl $D "$(fw 40 $R $D $D fresh)" null)"
check "claude-limits: resets_at 1 s earlier at 900 s, refreshed" "written $(fl $((D + 900)) "$(fw 40 $R $D $D fresh)" null)" \
  "$(step $((D + 900)) "$(in7 40 $((R - 1)))" "$(ts d9 $D)") $(cat "$lfile")"
# 9. A file from the old writer: read, and upgraded on the next write.
put "$(fl 2000 "$(w 50 $R)" "$(w 10 $F)")"
check "claude-limits: 9. an old file is upgraded, its values kept" "written $(fl 2010 "$(ns 50 $R 2000)" "$(ns 10 $F 2000)")" \
  "$(step 2010 "$(in7 40 $R)") $(cat "$lfile")"
put "$(fl 2000 "$(w 88 $R)" null)"
check "claude-limits: 9. an old file's value loses to fresh evidence" "written $(fl 2010 "$(fw 42 $R 2005 2010 fresh)" null)" \
  "$(step 2010 "$(in7 42 $R)" "$(ts old9 2005)") $(cat "$lfile")"
cp "$lfile" "$work/lim.before"
lim 2020 <<<"$(sl "$(in7 41 $R)" | jq -c '.transcript_path = 7')" >/dev/null
check "claude-limits: a transcript_path that is not a string is no evidence" "same" \
  "$(cmp -s "$lfile" "$work/lim.before" && echo same || echo differs)"

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
  "$(fl 1500 "$(ns 34 1795078800 1500)" null)" "$(cat "$lfile")"

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
check "claude-limits: inside herdr, labels still set" "label t3" "$(grep -x -A 1 label "$HC_LOG" | paste -sd ' ')"
check "claude-limits: inside herdr, the file too" "1900" "$(jq .written_at "$lfile")"

# ---- claude-statusline.sh ----
# Status-line input with `prompt_cache` = $1, as Claude Code 2.1.322 sends it,
# cut to the fields the script reads. `hc get` answers with a terminal whose
# agent.cache_session label is $CACHE_OF.
mkdir "$work/slbin"
cat >"$work/slbin/hc" <<EOF
#!$BASH
if [ "\$1" = get ]; then printf '{"labels":{"agent.cache_session":"%s"}}\n' "\${CACHE_OF:-}"; exit; fi
printf '%s\n' "\$@" >>"\$HC_LOG"
EOF
chmod +x "$work/slbin/hc"
cache() {
  : >"$HC_LOG"
  jq -nc --argjson c "$1" '{session_id: "s1", model: {display_name: "Fable 5.2"}, effort: {level: "high"}, version: "2.1.322",
    context_window: {used_percentage: 14.2, total_input_tokens: 139500}, prompt_cache: $c}' |
    HC_TERMINAL_ID=t4 PATH="$work/slbin:$work/limbin:$PATH" bash -euo pipefail "$scripts/claude-statusline.sh" >/dev/null
  grep -E '^agent\.cache' "$HC_LOG" | paste -sd ' '
}
check "claude-statusline: the cache's expiry and lifetime" "agent.cache_until=1795041084 agent.cache_ttl=1h agent.cache_session=s1" \
  "$(cache '{"warm":true,"caching_observed":true,"ttl":"1h","expires_at":1795041084.6}')"
check "claude-statusline: a 5-minute cache" "agent.cache_until=1795038309 agent.cache_ttl=5m agent.cache_session=s1" \
  "$(cache '{"warm":true,"caching_observed":true,"ttl":"5m","expires_at":1795038309}')"
check "claude-statusline: a missed cache is cold, its lifetime kept" "agent.cache_until=0 agent.cache_ttl=1h agent.cache_session=s1" \
  "$(cache '{"warm":false,"caching_observed":true,"ttl":"1h","expires_at":null}')"
check "claude-statusline: no caching seen yet clears them" "agent.cache_until= agent.cache_ttl= agent.cache_session=" \
  "$(cache '{"warm":false,"caching_observed":false,"ttl":"1h","expires_at":null}')"
check "claude-statusline: after another session's cache too" "agent.cache_until= agent.cache_ttl= agent.cache_session=" \
  "$(CACHE_OF=s0 cache '{"warm":false,"caching_observed":false,"ttl":"1h","expires_at":null}')"
check "claude-statusline: a resumed session keeps the cache it had" "" \
  "$(CACHE_OF=s1 cache '{"warm":false,"caching_observed":false,"ttl":"1h","expires_at":null}')"
check "claude-statusline: and still sets its other labels" \
  "label t4 agent.ctx=14 agent.ctxk=139 agent.model=Fable 5.2 agent.effort=high agent.version=2.1.322" "$(paste -sd ' ' "$HC_LOG")"
check "claude-statusline: all its labels, in one call" \
  "label t4 agent.ctx=14 agent.ctxk=139 agent.cache_until=0 agent.cache_ttl= agent.cache_session=s1 agent.model=Fable 5.2 agent.effort=high agent.version=2.1.322" \
  "$(cache '{"caching_observed":true}' >/dev/null; paste -sd ' ' "$HC_LOG")"

# ---- claude-title.sh ----
# `hc get` answers with terminal t7 as `hc get --json` gives it, cut to what
# the script reads, with $TITLE_LABELS as its labels; `hc label` is logged on
# one line. The hook's input is as Claude Code 2.1.322 sends it, cut to the
# fields a hook can count on: `session_title` only for a session with a custom
# name, `source` only on SessionStart.
mkdir "$work/titlebin"
cat >"$work/titlebin/hc" <<FAKE
#!$BASH
case \$1 in
  get)
    [ -z "\${HC_GET_FAILS:-}" ] || exit 1
    printf '{"address":"t7","name":null,"title":"x","state":"live","labels":%s}\n' "\$TITLE_LABELS"
    ;;
  *)
    echo "\$*" >>"\$HC_LOG"
    [ -z "\${HC_LABEL_FAILS:-}" ] || exit 1
    ;;
esac
FAKE
chmod +x "$work/titlebin/hc"
printf hi >"$work/prompt"
# Runs the hook for event $2 (session named $3, SessionStart source $4) on a
# terminal with labels $1, the prompt being $PROMPT_FILE's text; prints what
# it printed, then what it labelled.
title() {
  : >"$HC_LOG"
  jq -nc --arg e "$2" --arg t "${3:-}" --arg s "${4:-}" --rawfile p "${PROMPT_FILE:-$work/prompt}" \
    '{session_id: "s-1", transcript_path: "/x/s-1.jsonl", cwd: "/x", hook_event_name: $e}
      + (if $e == "UserPromptSubmit" then {prompt: $p, permission_mode: "default"} else {} end)
      + (if $t == "" then {} else {session_title: $t} end)
      + (if $s == "" then {} else {source: $s} end)' |
    TITLE_LABELS=$1 HC_TERMINAL_ID=t7 PATH="$work/titlebin:$PATH" bash -euo pipefail "$scripts/claude-title.sh"
  echo "exit $?"
  cat "$HC_LOG"
}
gives() { printf '{"hookSpecificOutput":{"hookEventName":"%s","sessionTitle":"%s"}}\nexit 0\n' "${2:-UserPromptSubmit}" "$1"; }
taken='label t7 agent.name= agent.name_base='
named() { jq -nc --arg n "$1" --arg b "${2:-}" --arg s "${3-absent}" \
  '{"agent.name": $n, "agent.model": "Fable 5.2"} + (if $b == "" then {} else {"agent.name_base": $b} end)
    + (if $s == "absent" then {} else {"claude.title": ($s | tojson)} end)'; }

check "claude-title: a rename reaches a session never named" \
  "$(gives herdr-cleanup; echo "$taken claude.title=\"herdr-cleanup\"")" \
  "$(title "$(named herdr-cleanup 'Fix pane header labels' '')" UserPromptSubmit)"
check "claude-title: a rename replaces a name Claude Code still has" \
  "$(gives herdr-cleanup; echo "$taken claude.title=\"herdr-cleanup\"")" \
  "$(title "$(named herdr-cleanup old old)" UserPromptSubmit old)"
check "claude-title: a /rename after the workbench rename wins" \
  "$(printf '%s\n' 'exit 0' "$taken claude.title=\"from-claude\"")" \
  "$(title "$(named herdr-cleanup old old)" UserPromptSubmit from-claude)"
check "claude-title: a first /rename after the workbench rename wins" \
  "$(printf '%s\n' 'exit 0' "$taken claude.title=\"from-claude\"")" \
  "$(title "$(named herdr-cleanup 'Fix pane header labels' '')" UserPromptSubmit from-claude)"
# The terminal's title already read from-claude when the workbench renamed it.
check "claude-title: a /rename before the workbench rename loses" \
  "$(gives herdr-cleanup; echo "$taken claude.title=\"herdr-cleanup\"")" \
  "$(title "$(named herdr-cleanup from-claude old)" UserPromptSubmit from-claude)"
check "claude-title: a rename to the name Claude Code has is only dropped" \
  "$(printf '%s\n' 'exit 0' "$taken")" \
  "$(title "$(named same old same)" UserPromptSubmit same)"
# A label from before this hook existed: no base, no recorded name.
check "claude-title: a rename with nothing recorded is given" \
  "$(gives hyprland-boss; echo "$taken claude.title=\"hyprland-boss\"")" \
  "$(title "$(named hyprland-boss)" UserPromptSubmit new-sunshine)"
check "claude-title: a recorded name that isn't JSON counts as none" \
  "$(gives herdr-cleanup; echo "$taken claude.title=\"herdr-cleanup\"")" \
  "$(title '{"agent.name":"herdr-cleanup","claude.title":"garbage"}' UserPromptSubmit new-sunshine)"

check "claude-title: no rename, a name not recorded yet is recorded" \
  "$(printf '%s\n' 'exit 0' 'label t7 claude.title="new-sunshine"')" \
  "$(title '{"agent.model":"Fable 5.2"}' UserPromptSubmit new-sunshine)"
check "claude-title: no rename, a session never named is recorded as such" \
  "$(printf '%s\n' 'exit 0' 'label t7 claude.title=""')" "$(title '{}' UserPromptSubmit)"
check "claude-title: no rename and nothing new labels nothing" "exit 0" \
  "$(title '{"claude.title":"\"new-sunshine\""}' UserPromptSubmit new-sunshine)"
check "claude-title: a terminal without labels" \
  "$(printf '%s\n' 'exit 0' 'label t7 claude.title=""')" "$(title null UserPromptSubmit)"

for source in startup resume fork; do
  check "claude-title: SessionStart $source takes a rename" \
    "$(gives herdr-cleanup SessionStart; echo "$taken claude.title=\"herdr-cleanup\"")" \
    "$(title "$(named herdr-cleanup old old)" SessionStart old "$source")"
done
# Claude Code ignores a title from these: the rename waits for the next prompt.
for source in clear compact; do
  check "claude-title: SessionStart $source keeps a rename, records the name" \
    "$(printf '%s\n' 'exit 0' 'label t7 claude.title=""')" \
    "$(title "$(named herdr-cleanup old old)" SessionStart '' "$source")"
done
check "claude-title: and the prompt after a /clear takes it" \
  "$(gives herdr-cleanup; echo "$taken claude.title=\"herdr-cleanup\"")" \
  "$(title "$(named herdr-cleanup old '')" UserPromptSubmit)"
check "claude-title: any other event only records the name" \
  "$(printf '%s\n' 'exit 0' 'label t7 claude.title="old"')" \
  "$(title "$(named herdr-cleanup)" Stop old)"

odd='Fix "é" & \back $(x) 日本'
check "claude-title: a name with quotes, a backslash and unicode comes out as JSON" "$odd" \
  "$(title "$(named "$odd")" UserPromptSubmit | head -n 1 | jq -r .hookSpecificOutput.sessionTitle)"
check "claude-title: and is recorded whole" "$taken claude.title=$(jq -nc --arg n "$odd" '$n')" \
  "$(title "$(named "$odd")" UserPromptSubmit | tail -n 1)"
check "claude-title: a prompt longer than an argument may be" "$(gives herdr-cleanup | head -n 1)" \
  "$(head -c 300000 /dev/zero | tr '\0' a >"$work/long"; PROMPT_FILE="$work/long" title "$(named herdr-cleanup)" UserPromptSubmit | head -n 1)"

check "claude-title: the core not answering, nothing printed, the prompt goes on" "exit 0" \
  "$(HC_GET_FAILS=1 title "$(named herdr-cleanup)" UserPromptSubmit)"
check "claude-title: a label that can't be set, the name is still given" \
  "$(gives herdr-cleanup; echo "$taken claude.title=\"herdr-cleanup\"")" \
  "$(HC_LABEL_FAILS=1 title "$(named herdr-cleanup)" UserPromptSubmit)"
check "claude-title: input that isn't JSON, nothing printed, the prompt goes on" "exit 0" \
  "$(: >"$HC_LOG"; echo 'not json' | TITLE_LABELS="$(named herdr-cleanup)" HC_TERMINAL_ID=t7 PATH="$work/titlebin:$PATH" \
    bash -euo pipefail "$scripts/claude-title.sh"; echo "exit $?"; cat "$HC_LOG")"
check "claude-title: outside herdr, nothing" "exit 0" \
  "$(: >"$HC_LOG"; echo '{"hook_event_name":"UserPromptSubmit"}' | (unset HC_TERMINAL_ID; PATH="$work/titlebin:$PATH" \
    bash -euo pipefail "$scripts/claude-title.sh"; echo "exit $?"); cat "$HC_LOG")"

# Claude Code would read anything agent-ask printed on this event as hook output.
check "agent-ask: prints nothing on UserPromptSubmit" "" \
  "$(echo '{"hook_event_name":"UserPromptSubmit","prompt":"hi"}' | HC_TERMINAL_ID=t2 bash -euo pipefail "$scripts/agent-ask.sh")"

exit "$failed"

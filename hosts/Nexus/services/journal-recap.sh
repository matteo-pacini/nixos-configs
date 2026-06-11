#!/usr/bin/env bash
set -euo pipefail

# Expected from the systemd unit:
#   TELEGRAM_ENV_FILE - agenix env file (BOT_TOKEN, CHANNEL_ID)
#   CLAUDE_ENV_FILE   - agenix env file (CLAUDE_CODE_OAUTH_TOKEN
#                       from `claude setup-token`)
#   STATE_DIRECTORY   - provided by StateDirectory=
#   PATH              - journalctl, systemctl, claude, telegram-notify, coreutils

# Export CLAUDE_CODE_OAUTH_TOKEN for the claude CLI.
set -a
# shellcheck disable=SC1090
source "$CLAUDE_ENV_FILE"
set +a

CURSOR_FILE="$STATE_DIRECTORY/cursor"

# Cursor file = no gaps/overlaps between runs. journalctl (systemd 260)
# refuses --cursor-file combined with --since, and a missing cursor file
# means "from the beginning of the journal" - so the first run bounds the
# window manually and saves the cursor itself.
if [[ -f "$CURSOR_FILE" ]]; then
  ERRORS=$(journalctl -p err -q --no-pager -o short-iso \
    --cursor-file="$CURSOR_FILE")
else
  OUT=$(journalctl -p err -q --no-pager -o short-iso \
    --since "-6h" --show-cursor)
  CURSOR=$(printf '%s\n' "$OUT" | sed -n 's/^-- cursor: //p')
  if [[ -n "$CURSOR" ]]; then
    printf '%s\n' "$CURSOR" > "$CURSOR_FILE"
  fi
  ERRORS=$(printf '%s\n' "$OUT" | grep -v '^-- cursor:' || true)
fi

if [[ -z "$ERRORS" ]]; then
  exit 0
fi

PROMPT='You are summarizing systemd journal errors (priority err and above) from the NixOS home server "Nexus", collected since the last run. The raw journal lines are on stdin.

Produce a Telegram-friendly digest, max 3000 characters, plain text only - no Markdown, no backticks, no asterisks, no underscores:

1. One-line overview: error count and which units are involved.
2. Grouped findings: per unit, count and one representative message, deduplicated.
3. "Worth a look": only things that need action, each with the next diagnostic command to run. You may run the allowed read-only commands (systemctl status, journalctl) to add context before deciding.

If everything is routine noise (e.g. misclassified info logs from containers), say so in one line and keep the digest short.

The very first line of your reply must be exactly ALERT or exactly OK. If you write anything under "Worth a look", the first line must be ALERT - never pair an OK marker with a non-empty "Worth a look" section. If nothing needs action, omit the section entirely and use OK. The digest starts on the second line.'

DIGEST=$(printf '%s\n' "$ERRORS" | claude -p "$PROMPT" \
  --model sonnet \
  --max-budget-usd 0.50 \
  --no-session-persistence \
  --output-format text \
  --allowedTools "Bash(journalctl:*),Bash(systemctl status:*),Bash(systemctl list-units:*),Read,Grep,Glob" \
  ) || DIGEST=""

if [[ -z "$DIGEST" ]]; then
  STATUS="ALERT" # pipeline failure is always worth a ping
  DIGEST="claude digest failed, raw errors:
$ERRORS"
else
  STATUS=$(printf '%s' "$DIGEST" | head -n 1 | tr -d '[:space:]')
  case "$STATUS" in
    ALERT | OK) DIGEST=$(printf '%s' "$DIGEST" | tail -n +2) ;;
    *) STATUS="ALERT" ;; # claude ignored the marker - assume actionable
  esac
fi

if [[ -n "${FORCE_ALERT:-}" ]]; then
  STATUS="ALERT"
fi

# Group mute can't be bypassed by the Bot API, but Telegram clients notify on
# @mentions even in muted groups - so actionable digests mention the admin.
MENTION=""
if [[ "$STATUS" == "ALERT" && -n "${ALERT_MENTION:-}" ]]; then
  MENTION=" $ALERT_MENTION"
fi

# telegram-notify sends with parse_mode=Markdown; strip characters that can
# break Telegram's parser, and respect the 4096-char message cap.
DIGEST=$(printf '%s' "$DIGEST" | tr -d '*_`[]')

telegram-notify "⚠️ Nexus journal recap$MENTION

${DIGEST:0:3800}"

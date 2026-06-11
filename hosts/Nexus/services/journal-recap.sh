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

# Cursor file = no gaps/overlaps between runs; --since only applies on the
# first run, when the cursor file does not exist yet.
ERRORS=$(journalctl -p err -q --no-pager -o short-iso \
  --cursor-file="$CURSOR_FILE" --since "-6h" || true)

if [[ -z "$ERRORS" ]]; then
  exit 0
fi

PROMPT='You are summarizing systemd journal errors (priority err and above) from the NixOS home server "Nexus", collected since the last run. The raw journal lines are on stdin.

Produce a Telegram-friendly digest, max 3000 characters, plain text only - no Markdown, no backticks, no asterisks, no underscores:

1. One-line overview: error count and which units are involved.
2. Grouped findings: per unit, count and one representative message, deduplicated.
3. "Worth a look": only things that need action, each with the next diagnostic command to run. You may run the allowed read-only commands (systemctl status, journalctl) to add context before deciding.

If everything is routine noise (e.g. misclassified info logs from containers), say so in one line and keep the digest short.'

DIGEST=$(printf '%s\n' "$ERRORS" | claude -p "$PROMPT" \
  --model sonnet \
  --max-budget-usd 0.50 \
  --no-session-persistence \
  --output-format text \
  --allowedTools "Bash(journalctl:*),Bash(systemctl status:*),Bash(systemctl list-units:*),Read,Grep,Glob" \
  ) || DIGEST=""

if [[ -z "$DIGEST" ]]; then
  DIGEST="claude digest failed, raw errors:
$ERRORS"
fi

# telegram-notify sends with parse_mode=Markdown; strip characters that can
# break Telegram's parser, and respect the 4096-char message cap.
DIGEST=$(printf '%s' "$DIGEST" | tr -d '*_`[]')

telegram-notify "⚠️ Nexus journal recap

${DIGEST:0:3800}"

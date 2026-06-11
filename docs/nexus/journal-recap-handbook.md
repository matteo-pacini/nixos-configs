# Nexus Journal Recap Handbook

Every 6 hours, a systemd timer collects journal errors since the last
run and has the Claude CLI turn them into a short digest, delivered to
the "Nexus Mark II" Telegram group via `telegram-notify`. Routine-noise
digests arrive silently; actionable ones @mention the admin, which
pierces a muted group. Built 2026-06-11 (PRs #295–#297).

## Quick Reference

| Item | Value |
|------|-------|
| Timer / service | `journal-recap.timer` → `journal-recap.service` (oneshot) |
| Schedule | `OnCalendar=0/6:00:00` (00/06/12/18), `Persistent`, 5 min jitter |
| Script | `hosts/Nexus/services/journal-recap.sh` (plain bash, no Nix templating) |
| Unit wiring | `hosts/Nexus/services/journal-recap.nix` |
| Cursor (state) | `/var/lib/private/journal-recap/cursor` (`DynamicUser` — `/var/lib/journal-recap` is a root-only symlink into it) |
| Claude auth | agenix `nexus/claude.env` (`CLAUDE_CODE_OAUTH_TOKEN`, subscription) |
| Telegram auth | agenix `nexus/janitor.env` (shared with smartd/mdadm/snapraid alerts) |
| Model / guard | `--model sonnet`, `--max-budget-usd 0.50` |
| Alert mention | `alertMention = "@matteopacini"` in `journal-recap.nix` |
| Test command | `sudo journal-recap-test [alert]` |
| Exposure score | 1.5 OK (`systemd-analyze security`; 9.6 UNSAFE unhardened) |

---

## Pipeline

1. **Collect.** `journalctl -p err` (priority `err` and above) since the
   saved cursor. No new errors → exit silently, no message.
2. **Digest.** Errors are piped to `claude -p` (Sonnet) with read-only
   tools allowed (`Bash(journalctl:*)`, `Bash(systemctl status:*)`,
   `Bash(systemctl list-units:*)`, `Read`, `Grep`, `Glob`) so it can
   gather context before writing. The prompt asks for: one-line
   overview, findings grouped per unit, and a "Worth a look" section
   with next diagnostic commands. Plain text only (no Markdown — see
   Telegram notes below).
3. **Route.** Claude's first line is a marker: `ALERT` (something
   actionable) or `OK` (routine noise). The prompt forbids pairing `OK`
   with a non-empty "Worth a look" section. The marker is stripped
   before sending. `ALERT` — or a pipeline failure, or a missing
   marker — adds the @mention to the message header.
4. **Send.** `telegram-notify` posts the digest to the group. If the
   claude call fails or returns nothing, the raw (truncated) errors are
   sent instead, always with the mention.

### Cursor handling

`--cursor-file` gives gapless, non-overlapping windows between runs,
but two systemd 260 quirks shape the first run:

- `--cursor-file` cannot be combined with `--since` ("Please specify
  only one of…").
- A missing cursor file means "from the beginning of the journal", not
  "from now".

So the first run (no cursor file) uses `--since "-6h" --show-cursor`,
parses the `-- cursor:` trailer, and writes the cursor file itself.
Every later run uses `--cursor-file` alone. journalctl failures fail
the unit visibly rather than being swallowed.

**Reset:** delete `/var/lib/private/journal-recap/cursor`; the next
run re-baselines to the last 6 hours.

### Claude invocation notes

- Auth is a long-lived subscription OAuth token from
  `claude setup-token`, stored in agenix `nexus/claude.env` and
  exported as `CLAUDE_CODE_OAUTH_TOKEN`. It bills the Claude
  subscription, not API credits. `--bare` must NOT be used — it
  restricts auth to `ANTHROPIC_API_KEY` and ignores OAuth tokens.
- claude-code 2.1.170 has no `--max-turns`; `--max-budget-usd` is the
  runaway guard (may be a no-op on subscription auth — the raw-error
  fallback covers a failed/empty digest either way).
- `HOME` is pointed at the state directory so claude's config/cache
  stay out of `/root`. `--no-session-persistence` keeps runs stateless.

### Telegram notes (why mention, not pin or DM)

The Bot API cannot bypass a user's mute: `disable_notification` only
controls sound ("Users will receive a notification with no sound").
Ways to ping through a mute, from the API docs:

- **@mention** (used here): Telegram clients notify on mentions even in
  muted groups. Client-side behavior — a user can disable the mention
  exception in notification settings.
- **Pin**: `pinChatMessage` notifies all members, but "Notifications
  are always disabled in channels and private chats" — groups only,
  needs pin rights, second API call. Not used.
- **DM from the bot**: separate chat with its own notification
  settings. Not used (alerts stay in the group).

`telegram-notify` sends with `parse_mode=Markdown`, so the script
strips `` * _ ` [ ] `` from the digest to avoid parse failures
(a parse error makes the API reject the message). Message cap is 4096
chars; the digest is truncated to 3800.

---

## Service hardening

The unit runs fully unprivileged (PR #298, verified live 2026-06-11:
exposure 9.6 UNSAFE → 1.5 OK, clean run, 467M peak memory).

The two pieces that remove the need for root:

- **`DynamicUser=true` + `LoadCredential=`** — systemd loads the agenix
  secrets as root and exposes them read-only in the per-run credentials
  directory; the unit passes `TELEGRAM_ENV_FILE=%d/janitor.env` and
  `CLAUDE_ENV_FILE=%d/claude.env` (`%d` = credentials dir). The service
  itself runs as a throwaway user.
- **`SupplementaryGroups=systemd-journal`** — journal read access
  without root.

On top: `ProtectSystem=strict`, `ProtectHome`, `PrivateTmp`,
`PrivateDevices`, `ProtectKernel{Tunables,Modules,Logs}`,
`ProtectProc=invisible`, `ProtectClock`, `ProtectControlGroups`,
`ProtectHostname`, `CapabilityBoundingSet=""`, `NoNewPrivileges`,
`RestrictAddressFamilies=UNIX/INET/INET6`, `RestrictNamespaces`,
`RestrictSUIDSGID`, `RestrictRealtime`, `LockPersonality`,
`SystemCallArchitectures=native`, `SystemCallFilter=@system-service`,
`UMask=0077`, `MemoryMax=2G`, `TimeoutStartSec=15min` (oneshot
runtime cap).

Deliberate exclusions — claude is a Bun binary, and Bun has runtime
requirements that standard hardening sets break:

| Omitted / adjusted | Why |
|--------------------|-----|
| `io_uring_{setup,enter,register}` allowed explicitly | Bun does I/O via io_uring; `@system-service` contains none of them (verified on Nexus) |
| No `MemoryDenyWriteExecute` | Bun's JIT needs writable+executable pages |
| No `PrivateUsers` | Breaks the `systemd-journal` group mapping → no journal access |
| No `ProcSubset=pid` | Hides `/proc/meminfo` from the JS runtime |

If a future claude-code bump starts failing under the sandbox, suspect
the syscall filter first, then `RestrictNamespaces`, then
`ProtectProc` — loosen one at a time and re-check the score.

`journal-recap-test` is unaffected by all of this: it runs outside the
unit, as root via sudo, with direct secret paths.

---

## Testing

```bash
sudo journal-recap-test          # routine path
sudo journal-recap-test alert    # forces the mention path
```

Runs the exact same script as the timer, but with a throwaway
`STATE_DIRECTORY` (temp dir): the fresh cursor falls back to the last
6 hours, so the test always has material and is repeatable, and the
real timer cursor never moves. Sends to the real group. `alert` sets
`FORCE_ALERT=1`, which only overrides the routing decision — digest
content is still the real pipeline. `sudo` is required because the
agenix secrets are root-only.

Verified 2026-06-11: API response carried
`entities: [{type: "mention"}]` and the muted group notified.

---

## Operations

```bash
# Next/last run
systemctl list-timers journal-recap

# Service logs
journalctl -u journal-recap.service -n 50

# Cursor state (DynamicUser state lives under /var/lib/private)
sudo cat /var/lib/private/journal-recap/cursor
```

**Change the interval:** edit `OnCalendar` in `journal-recap.nix`.

**Change the mention handle:** edit `alertMention` in
`journal-recap.nix`.

**Rotate the Claude token:** run `claude setup-token` on any machine,
then re-create the secret (encryption only needs the Nexus public key
from `secrets/secrets.nix` — no decryption of the old file required,
since the token is the file's only content):

```bash
umask 077
printf 'CLAUDE_CODE_OAUTH_TOKEN=<new token>\n' > /tmp/claude.env
nix run nixpkgs#age -- -r "<nexus ssh-ed25519 public key>" \
  -o secrets/nexus/claude.env.age /tmp/claude.env
rm /tmp/claude.env
```

Commit, rebuild Nexus, then revoke the old token from claude.ai
settings.

**Tune the digest:** the prompt lives in `journal-recap.sh`. The
ALERT/OK first-line contract must survive any prompt edit — the script
routes on it.

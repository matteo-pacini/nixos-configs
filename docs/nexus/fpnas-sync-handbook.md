# fpnas Sync Handbook

`fpnas` is the source of truth for the `fabrizio` user's files. Nexus mirrors it into `/diskpool/fabrizio` every night, and the `fabrizio` restic repo backs that copy up to B2. Connection details live in `hosts/Nexus/services/fpnas-sync.nix`.

## Nightly chain

| Time | Unit | What |
|------|------|------|
| 02:00 | `fpnas-sync.service` | `rsync --delete` pull from fpnas, as user `fabrizio`, 50 min cap |
| 03:00 | `backup-job.service` | Waits for `fpnas-sync` if it is still running; ends with SnapRAID sync |
| 06:00 | `restic-backups-fabrizio.service` | B2 snapshot of `/diskpool/fabrizio` |

`backup-job` does not require `fpnas-sync`. If fpnas is offline, the sync fails, Telegram reports it, and the rest of the backup runs as normal.

## What is mirrored

- Synology metadata and junk are not copied: see the `--exclude` list in the unit.
- `/diskpool/fabrizio/nexus-only/` holds files that exist only on Nexus (gone from fpnas). The unit's `P` filter keeps `--delete` from removing it. Before a deletion-heavy first run, move such files there with their relative paths.
- Anything else written directly into `/diskpool/fabrizio` is deleted on the next run. Changes belong on fpnas.

## Access

- The unit authenticates with the agenix secret `nexus/fpnas-sync-key` (owner `fabrizio`, mode 400) and checks fpnas against the host key pinned in `programs.ssh.knownHosts.fpnas`.
- Files are owned by `fabrizio:users`. Directories carry a default ACL that grants `matteo` access and nobody else. rsync runs with `--no-perms`, so new files take their mode from that ACL.
- New directories created by hand under `/diskpool/fabrizio` need the same default ACL:
  ```bash
  sudo setfacl -d -m u::rwx,u:matteo:rwx,g::---,o::---,m:rwx <dir>
  ```

## When `--max-delete` trips

rsync stops deleting after the cap set in the unit and exits 25, and Telegram reports a failure. This is either a big reorganisation on fpnas or a mass deletion there. Look before forcing anything:

```bash
journalctl -u fpnas-sync -n 100
```

To see what a run would delete, copy the rsync line from the unit's script (`systemctl cat fpnas-sync`), add `-n --itemize-changes`, run it as `sudo -u fabrizio`, and grep for `*deleting`. If the deletions are intended, run it once without `-n` and without `--max-delete`. If they are not, deleted files are still in the fpnas recycle bin and in the restic snapshots (`restic-b2 fabrizio snapshots`).

## Key rejected

If the unit fails with `Permission denied (publickey…)`, check the key's entry in `authorized_keys` on fpnas, and that the account's home directory and `.ssh` are not group- or world-writable.

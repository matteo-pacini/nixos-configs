# Nexus Disk Failure Handbook

Runbook for diagnosing and retiring a failing data disk in the Nexus
mergerfs + SnapRAID pool. The worked example uses `disk1` (sda),
retired 2026-05-27 after repeated SMART self-test failures; substitute
your own disk number throughout.

Companion to [`diskpool-handbook.md`](diskpool-handbook.md), which
describes the steady-state layout.

> **If you change the Nexus disk layout, update this handbook.** The
> commands here reference specific disk numbers and the canonical
> service list lives in `hosts/Nexus/services/backup.nix`. If you add,
> remove, or renumber data disks, walk through this doc and adjust.

---

## Quick reference: files touched during a retirement

| File | What changes |
|------|--------------|
| `hosts/Nexus/hardware-extra.nix` | Filter the disk out of `diskNumbers`; comment its crypttab line |
| `hosts/Nexus/snapraid.nix` | Filter the disk out of `diskNumbers` |
| `secrets/secrets.nix` | Comment the `nexus/diskN.age` declaration |
| `docs/nexus/diskpool-handbook.md` | Update inventory table to reflect the new layout |

The encrypted `.age` file itself can stay in `secrets/nexus/`; it
becomes orphaned but harmless once the consumer is removed.

---

## Phase 0 — Diagnose

Triggered by a Telegram alert from `smartd`, a kernel I/O error in
`journalctl`, or a routine SMART check.

```bash
# Identify the device (SAS — output differs slightly from SATA).
sudo smartctl -i /dev/sdX

# Health summary + attributes.
sudo smartctl -H -A /dev/sdX

# Self-test log and per-LBA error log.
sudo smartctl -l selftest /dev/sdX
sudo smartctl -l error    /dev/sdX

# Kernel-level I/O errors against the device.
journalctl -k --since "7 days ago" | grep -iE "sdX|ata|medium"
```

### What signals matter

| Signal | Meaning |
|--------|---------|
| `Elements in grown defect list > 0` (SAS) or `Reallocated_Sector_Ct > 0` (SATA) | Real bad sectors — drive remapping has started |
| `Current_Pending_Sector > 0` | Sectors flagged for reallocation on next write — degrading |
| `read: uncorrected errors > 0` | Actual unrecoverable read errors during normal I/O |
| Kernel `ata` resets, `medium error` messages against the device | Disk is misbehaving at the controller level |
| Self-test `Failed in segment` with an LBA and sense data | Real media failure — confirms a bad region |
| Self-test `Failed in segment` with **no** LBA and **no** sense data | Ambiguous on SAS — could still indicate degradation; do not dismiss as firmware noise without corroboration |

### What is not enough

A clean defect list does not prove a drive is healthy when self-tests
repeatedly fail. SAS SMART reporting is sparser than SATA — see the
TrueNAS community discussions linked from the May 2026 incident notes
for the rationale.

If you only have self-test failures and no other corroboration, run a
long test (`smartctl -t long /dev/sdX`) and watch whether it fails
quickly (well before the estimated duration) or at the expected
runtime. Failing fast at the same segment as short tests, repeatedly,
is enough to act.

---

## Phase 1 — Decide approach

| | Drain (Approach A) | SnapRAID rebuild (Approach B) |
|---|--------------------|-------------------------------|
| Pre-condition | Source disk still readable | Drive dead, or replacement on hand |
| Outcome | Pool shrinks (one fewer data disk) | Pool size unchanged, disk replaced |
| Needs replacement disk | No | Yes |
| Wall time | ~1 h per TiB at sequential rate | Depends on disk size and rebuild speed |
| Risk during procedure | Source could fail mid-drain (parity recovers) | None new — disk is already out |

Default to **Approach A** when the disk is still reading cleanly and
the remaining pool has room to absorb its contents (`df -h /mnt/disk*`
and confirm `sum(free elsewhere) > used on failing disk`). The May
2026 retirement followed Approach A.

Switch to **Approach B** if the disk is throwing kernel I/O errors,
the rsync is failing on specific files, or you specifically want to
preserve the 10-disk layout.

---

## Approach A — Drain the failing disk

### A1. Pre-flight

```bash
# Confirm room. Sum of free on remaining data disks must exceed used
# on the failing disk.
df -h /mnt/disk*

# Confirm SnapRAID is currently in sync. If not, resolve before
# starting (a clean parity is your fallback if the drain stalls).
sudo snapraid status
```

Identify processes touching `/diskpool`:

```bash
sudo lsof +D /diskpool 2>/dev/null | awk 'NR>1 {print $1}' | sort -u
```

### A2. Quiesce writers

Cross-reference with `hosts/Nexus/services/backup.nix` — that file
already enumerates the services that the nightly backup stops, which
is exactly the set we need to stop here. **Critically, mask
`backup.timer` first** — its job ends with `snapraid sync`, which
would corrupt parity if it ran mid-drain.

```bash
# Timers that would fire during the drain window.
sudo systemctl stop \
  backup.timer snapraid-scrub.timer \
  restic-backups-config.timer restic-backups-matteo.timer \
  restic-backups-debora.timer restic-backups-fabrizio.timer

# Mask with --runtime (see note below — plain `mask` fails on NixOS).
sudo systemctl mask --runtime \
  backup.timer snapraid-scrub.timer \
  restic-backups-config.timer restic-backups-matteo.timer \
  restic-backups-debora.timer restic-backups-fabrizio.timer

# Verify masking took — authoritative check is the NEXT column of
# list-timers; a masked timer will show `-`. Do NOT rely on
# `systemctl is-enabled`, which only reports the on-disk unit state
# and will still say "enabled" for a runtime-masked NixOS unit.
systemctl list-timers --all backup.timer snapraid-scrub.timer 'restic-backups-*.timer'
ls -la /run/systemd/system/backup.timer    # expect -> /dev/null

# Confirm no backup is currently running.
sudo systemctl is-active \
  backup-job.service ha-backup.service snapraid-scrub.service \
  restic-backups-config.service restic-backups-matteo.service \
  restic-backups-debora.service restic-backups-fabrizio.service
# Expect all 'inactive'.

# Application services (mirror of backup.nix `haServices` and
# `affectedServices`).
sudo systemctl stop \
  home-assistant mosquitto zigbee2mqtt
sudo systemctl stop \
  jellyfin nzbget nzbhydra2 radarr sonarr \
  paperless-web paperless-scheduler paperless-consumer paperless-task-queue \
  phpfpm-nextcloud nginx
sudo systemctl stop podman-compose-nexus-n8n-root.target
sudo systemctl stop \
  nextcloud-cron.timer nextcloud-scan-external.timer
sudo systemctl stop \
  nextcloud-cron.service nextcloud-scan-external.service 2>/dev/null || true

# Verify nothing left writing.
sudo lsof +D /diskpool
```

### A3. Drop the disk from mergerfs (runtime)

Capture current branches first so you have a restore path if anything
goes sideways:

```bash
getfattr -n user.mergerfs.branches /diskpool/.mergerfs | tee /tmp/mergerfs-branches.bak
```

Then set the new branch list **without** the failing disk. Replace the
example value below with your remaining disks:

```bash
# Example for retiring disk1:
sudo setfattr -n user.mergerfs.branches \
  -v "/mnt/disk0=RW:/mnt/disk2=RW:/mnt/disk3=RW:/mnt/disk4=RW:/mnt/disk5=RW:/mnt/disk6=RW:/mnt/disk7=RW:/mnt/disk8=RW:/mnt/disk9=RW" \
  /diskpool/.mergerfs

# Verify.
getfattr -n user.mergerfs.branches /diskpool/.mergerfs
df -h /diskpool   # Size should drop by the failing disk's capacity
```

The xattr change is in-memory only — it reverts on remount or reboot.
For the duration of the drain that is fine.

### A4. Plan the partition

Direct rsync to specific destination disks is several times faster
than rsyncing through `/diskpool` (FUSE overhead + scattered writes).
Pick destination disks with the most free space.

Get the breakdown of the failing disk:

```bash
sudo du -sh /mnt/diskN/*/ | sort -h
```

If the largest top-level directory exceeds the largest single
destination disk's free space, drill down to subdirectories and repeat
until you have shardable units (in the May 2026 case, `media/Library/`
was the level at which `Anime/`, `Movies/`, and `Tv Shows/` became
individually distributable).

For a directory containing many similarly-sized subdirs (movies, TV
shows), greedy bin-pack across N destination disks:

```bash
# Pack /mnt/diskN/path/with/many/subdirs/ into 3 buckets (disk2/3/8).
# Adjust output paths and arithmetic for your target disks.
sudo du -sb /mnt/diskN/path/*/ | sort -rn | awk '
BEGIN { d[2]=0; d[3]=0; d[8]=0; out[2]="/tmp/m2"; out[3]="/tmp/m3"; out[8]="/tmp/m8" }
{
  sz=$1; $1=""; sub(/^[[:space:]]+/,"")
  pick=2; for (k in d) if (d[k]<d[pick]) pick=k
  d[pick]+=sz
  print >> out[pick]
}
END {
  for (k in d) printf "disk%d: %.1f GiB\n", k, d[k]/(1024^3) > "/dev/stderr"
}'
wc -l /tmp/m2 /tmp/m3 /tmp/m8
```

The greedy-by-size pass keeps bucket totals within a few GiB even when
the underlying items vary in size — verify the printed totals before
proceeding.

### A5. Drain (serial, in tmux)

**Run rsyncs serially, not in parallel.** Multiple concurrent readers
on a single failing SAS spinner cause head-seek storms that drop
aggregate throughput well below what a single sequential reader
achieves. With a single reader you should see 100–200 MB/s on healthy
media.

```bash
tmux new -s drain

# Job 1: everything except the big shardable subtree -> first dest.
sudo rsync -aHAXS --info=progress2 --remove-source-files \
  --exclude='snapraid.content' --exclude='lost+found/' \
  --exclude='path/with/many/subdirs/' \
  /mnt/diskN/ /mnt/disk<destA>/

# Convert bucket paths to source-relative form (one-time prep).
for n in 2 3 8; do sed 's|^/mnt/diskN/||' /tmp/m$n > /tmp/m$n.rel; done

# Pre-create destination skeleton.
sudo mkdir -p /mnt/disk2/path/with/many/subdirs \
              /mnt/disk3/path/with/many/subdirs \
              /mnt/disk8/path/with/many/subdirs

# Job 2..N: one rsync per bucket.
sudo rsync -aHAXS --info=progress2 --remove-source-files \
  --files-from=/tmp/m2.rel /mnt/diskN/ /mnt/disk2/

sudo rsync -aHAXS --info=progress2 --remove-source-files \
  --files-from=/tmp/m3.rel /mnt/diskN/ /mnt/disk3/

sudo rsync -aHAXS --info=progress2 --remove-source-files \
  --files-from=/tmp/m8.rel /mnt/diskN/ /mnt/disk8/
```

Detach with `Ctrl-b d`, re-attach with `tmux attach -t drain`. Monitor
progress from another shell:

```bash
df --output=used /mnt/diskN     # shrinks as --remove-source-files runs
df -h /mnt/disk*                # destinations grow accordingly
```

If rsync errors on a specific file (source disk starts throwing read
errors mid-drain):

```bash
# Recover that file from SnapRAID parity, then resume rsync.
sudo snapraid -d dN -f /path/relative/to/diskN fix
```

Never run `snapraid sync` between Phases A3 and A8 — it would
overwrite parity for the old layout while you are mid-transition.

### A6. Verify empty

```bash
find /mnt/diskN -type f \
  ! -name 'snapraid.content' \
  ! -path '*/lost+found/*' | head -50
du -sh /mnt/diskN
```

The residual should be ~size of `snapraid.content` (typically a few
GiB) plus directory metadata. Cleanup:

```bash
sudo find /mnt/diskN -type d -empty -delete
sudo rm /mnt/diskN/snapraid.content
ls /mnt/diskN     # expect only 'lost+found/'
```

### A7. Commit the nix layout change

Edit the three files listed in the [Quick reference](#quick-reference-files-touched-during-a-retirement)
at the top. For the `diskNumbers` filter, use:

```nix
# diskN drained YYYY-MM-DD — <one-line reason>
# diskNumbers = lib.range 0 9;
diskNumbers = lib.filter (n: n != N) (lib.range 0 9);
```

Comment-style edits make the change reversible if you ever re-add the
slot (with a new physical disk). Eval first:

```bash
nix eval ".#nixosConfigurations.Nexus.config.system.build.toplevel.drvPath" 2>&1 | tail -3
```

Commit with semantic host scope:

```bash
git commit -m "fix(nexus): retire diskN (sdX) from data pool"
```

Then rebuild:

```bash
sudo nixos-rebuild switch --flake .#Nexus
```

After switch, `/etc/snapraid.conf` no longer lists the disk, and the
mergerfs mount no longer includes it (matching the runtime state from
A3).

### A8. Re-sync SnapRAID against the new layout

```bash
sudo snapraid sync       # rewrites parity for the 9-disk layout
sudo snapraid status     # confirm clean
```

This is the long step (multiple hours — both parity disks are
rewritten from scratch). Run in tmux.

### A9. Decommission the physical disk

```bash
# Re-enable timers stopped in A2 (use --runtime to match the mask).
sudo systemctl unmask --runtime \
  backup.timer snapraid-scrub.timer \
  restic-backups-config.timer restic-backups-matteo.timer \
  restic-backups-debora.timer restic-backups-fabrizio.timer
sudo systemctl start \
  backup.timer snapraid-scrub.timer \
  restic-backups-config.timer restic-backups-matteo.timer \
  restic-backups-debora.timer restic-backups-fabrizio.timer

# Restart application services.
sudo systemctl start \
  jellyfin nzbget nzbhydra2 radarr sonarr \
  paperless-web paperless-scheduler paperless-consumer paperless-task-queue \
  phpfpm-nextcloud nginx
sudo systemctl start podman-compose-nexus-n8n-root.target
sudo systemctl start nextcloud-cron.timer nextcloud-scan-external.timer
sudo systemctl start home-assistant mosquitto zigbee2mqtt

# Take the disk offline.
sudo umount /mnt/diskN
sudo cryptsetup close diskN

# Hot-pull is supported on the BP13G+EXP backplane.
```

Update `diskpool-handbook.md`:

- Remove the row from the disk inventory table
- Adjust the architecture diagram
- Fix the capacity totals
- Append a row to the **Changelog** section at the bottom

---

## Approach B — SnapRAID rebuild (replacement disk required)

Use this when the failing disk is unreadable, or when you want to keep
the disk count constant.

### B1. Quiesce writers

Same as A2 — in particular, `backup.timer` must be masked so it does
not run `snapraid sync` while the array is in a degraded state.

### B2. Physically replace the disk

```bash
# If still mounted, take it offline.
sudo umount /mnt/diskN || true
sudo cryptsetup close diskN || true

# Pull old disk, insert new disk, identify it.
lsblk
```

### B3. Encrypt and format the replacement

Re-use the existing LUKS UUID for the slot (so `hardware-extra.nix`
keeps working unchanged), or generate a fresh UUID and update the
crypttab entry.

```bash
# Format with the original UUID:
sudo cryptsetup luksFormat \
  --uuid <existing-luks-uuid> \
  --type luks2 --cipher aes-xts-plain64 --key-size 512 --hash sha256 \
  --pbkdf argon2id \
  /dev/sdY < /run/agenix/nexus/diskN

sudo cryptsetup open /dev/sdY diskN --key-file /run/agenix/nexus/diskN
sudo mkfs.ext4 /dev/mapper/diskN
sudo mount /mnt/diskN
```

If you generated a new UUID, update `hosts/Nexus/hardware-extra.nix`
crypttab and rebuild before mounting.

### B4. Rebuild from parity

```bash
sudo snapraid -d dN fix       # restores file content from parity
sudo snapraid check           # verify
sudo snapraid sync            # bring parity back into a clean state
```

### B5. Restore writers

Unmask timers and restart application services as in A9.

---

## Troubleshooting

### `systemctl mask` fails: "File already exists and is a symlink"

NixOS-managed units live in `/etc/systemd/system/<unit>` as symlinks
into `/nix/store/`. Plain `systemctl mask` tries to overwrite that
path with a symlink to `/dev/null` and fails because the original
symlink is already there.

Use `systemctl mask --runtime` instead — it creates the mask under
`/run/systemd/system/<unit>`, which takes precedence over `/etc/` at
runtime and doesn't touch the nix-store symlinks. The mask survives
`nixos-rebuild switch` (which doesn't write to `/run`) but resets on
reboot, which is exactly the lifetime we want for a maintenance
window. Unmask with `systemctl unmask --runtime <unit>`.

`systemctl is-enabled` will still report `enabled` for a
runtime-masked unit because it inspects the on-disk unit file, not
the runtime override. To confirm the mask is effective, check
`systemctl list-timers --all` (the `NEXT` column shows `-` for masked
timers) or list `/run/systemd/system/<unit>` (should be a symlink to
`/dev/null`).

### Mergerfs xattr change reverted mid-drain

A service restart or reboot reapplies the nix-defined branch list,
which re-introduces the failing disk. The drain rsyncs will then start
routing files back onto it.

Fix: stop, re-apply `setfattr` from A3, and restart the rsync.

If you want belt-and-braces, do the nix-side edit from A7 *before*
starting the drain — the rebuild then makes the branch change
persistent. The trade-off is you cannot fall back cleanly to the
original 10-disk layout without another rebuild.

### rsync throughput stuck at ~10 MB/s

You are probably writing through `/diskpool` (mergerfs FUSE) rather
than to a specific `/mnt/diskN/`. FUSE overhead and the mfs create
policy round-robining between physical disks both contribute. Switch
to direct-disk rsync (A4–A5).

### Source disk read errors during rsync

`rsync` will skip the file and report the error. Use
`snapraid -d dN -f <path> fix` to recover that specific file from
parity into its original location on the source disk, then resume the
rsync. `--remove-source-files` ensures rsync will not re-attempt files
it already moved.

### `snapraid sync` complains about block-size mismatch

`md127: echo current LBS to md/logical_block_size` appears at boot
when the SSDs report a different LBS than expected. Unrelated to the
drain — see kernel docs for the workaround.

---

## Related documents

- [Diskpool Handbook](diskpool-handbook.md) — steady-state layout
- [Paperless-ngx Recovery](paperless-ngx-recovery.md)
- `hosts/Nexus/services/backup.nix` — canonical service list
- `hosts/Nexus/hardware-extra.nix` — LUKS, fileSystems, mergerfs mount
- `hosts/Nexus/snapraid.nix` — SnapRAID configuration

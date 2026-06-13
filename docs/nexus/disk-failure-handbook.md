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
preserve the 9-disk layout.

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
is exactly the set we need to stop here. **Critically, stop
`backup.timer` first** — its job ends with `snapraid sync`, which
would corrupt parity if it ran mid-drain.

```bash
# Stop all timers that would fire during the drain window. `stop` is
# the right tool here — see the Troubleshooting section below for why
# `systemctl mask` (with or without --runtime) does not work on
# NixOS-managed units. Stopping disarms the timer; it will stay
# disarmed until something triggers a re-arm (a `nixos-rebuild
# switch`, a reboot, or `systemctl start`).
sudo systemctl stop \
  backup.timer snapraid-scrub.timer \
  restic-backups-config.timer restic-backups-matteo.timer \
  restic-backups-debora.timer restic-backups-fabrizio.timer \
  nextcloud-cron.timer nextcloud-scan-external.timer

# Verify — the NEXT column of list-timers must show `-` for every
# stopped timer. Do NOT rely on `systemctl is-enabled`; it reports
# the on-disk unit state and will still say "enabled".
systemctl list-timers --all backup.timer snapraid-scrub.timer 'restic-backups-*.timer' nextcloud-cron.timer nextcloud-scan-external.timer

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

Never run `snapraid sync` between Phases A3 and A7 — it would
overwrite parity for the old layout while files are mid-move. After
A7 the new layout is committed and A8 is exactly the right time to
sync.

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

Edit the three nix files listed in the [Quick reference](#quick-reference-files-touched-during-a-retirement)
at the top (the doc updates listed there are handled in A9). For the
`diskNumbers` filter, use:

```nix
# diskN drained YYYY-MM-DD — <one-line reason>
# Previous state (already excludes retired disk1):
# diskNumbers = lib.filter (n: n != 1) (lib.range 0 9);
diskNumbers = lib.filter (n: n != 1 && n != N) (lib.range 0 9);
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

**What `nixos-rebuild switch` does automatically — important:**

- **Unmounts** the removed `fileSystems."/mnt/diskN"` entry. You do
  *not* need to `umount /mnt/diskN` manually afterwards.
- **Restarts** application services that were merely `stop`ped (not
  permanently disabled) in A2, because the new generation still
  enables them. The pool comes back online for normal use.
- **Re-arms the timers stopped in A2.** The activation script
  reloads systemd and the timers come back to their armed state.
  If you need them stopped past the switch (e.g. you're about to
  run `snapraid sync` manually in A8 and don't want `backup.timer`
  firing in the middle of it), re-run the `systemctl stop ...` from
  A2 immediately after the rebuild completes.
- Does **not** close the LUKS mapping — `/dev/mapper/diskN` will
  still exist until A9.

Practical consequence: by the time `switch` finishes, the only
operational artefacts left are the open LUKS mapping (handled in A9)
and out-of-date parity (handled in A8).

### A8. Re-sync SnapRAID against the new layout

**The first sync after retirement cannot use the post-rebuild nix
config directly.** SnapRAID's content file still has block records
for the removed disk, and it refuses to silently drop them — `sync`
fails immediately with a misleading "Error decoding … at offset N"
followed by "Disk 'dN' … not present in the configuration file". The
`--force-zero` flag (which `backup.nix` already passes) is not
sufficient, and `--force-empty` on its own only applies to disks
*still listed* in the config but empty.

The supported workaround is to run a one-time sync against a
**temporary config** that re-introduces the removed disk pointing at
an empty placeholder. SnapRAID then rewrites the content file
without that disk's records, after which the nix-managed config
works normally.

```bash
# 1. Empty placeholder for the removed disk.
sudo mkdir -p /tmp/empty-diskN

# 2. Temp config = nix-generated config + a placeholder data line.
{ cat /etc/snapraid.conf; echo; echo 'data dN /tmp/empty-diskN'; } \
  | sudo tee /tmp/snapraid-resync.conf >/dev/null

# 3. Verify (data dN /tmp/empty-diskN should be the last data line).
grep -E '^(data|content|parity|2-parity)' /tmp/snapraid-resync.conf
ls /tmp/empty-diskN     # should be empty

# 4. Sync. BOTH flags are required: --force-zero (allow zero blocks)
#    and --force-empty (allow sync of the placeholder empty disk).
tmux new -s sync
sudo snapraid -c /tmp/snapraid-resync.conf --force-zero --force-empty sync
sudo snapraid -c /tmp/snapraid-resync.conf status   # confirm clean

# 5. Cleanup after success.
rm /tmp/snapraid-resync.conf
rmdir /tmp/empty-diskN
```

Multiple hours wall time — both parity disks are rewritten from
scratch.

After this one-time sync completes, the nix-managed `/etc/snapraid.conf`
(which does not list `dN`) is valid on its own and the nightly
`backup.timer` job will succeed the next time it runs. No further
manual intervention is needed.

### A9. Decommission the physical disk

By this point `switch` has already unmounted `/mnt/diskN` and brought
services + timers back online (see A7). The outstanding state is the
open LUKS mapping and the physical drive still slotted in the chassis.

#### A9.1 Detach the FS layer

```bash
# Sanity check — should already be unmounted by the rebuild.
mount | grep "/mnt/diskN" || echo "(unmounted)"

# Close the LUKS mapping (not done automatically by switch).
sudo cryptsetup close diskN

# Verify.
lsblk /dev/sdX                  # expect no children under sdX
ls /dev/mapper/diskN 2>&1       # expect "No such file or directory"
```

After this, `/dev/sdX` is a plain block device with no DM consumers and
no FS mounted on top. Safe to read; not yet detached from the kernel.

#### A9.2 Identify the physical drive

The Nexus chassis fronts a BP13G+EXP SAS expander backplane via an LSI
MegaRAID SAS-3 3108 (Invader). Three methods, in order of preference.

**Method 1 — `storcli` locate LED (RAID personality only).**

`storcli` is unfree and not in the system profile; pull it via
`nix-shell` on demand.

```bash
# Check personality first.
NIXPKGS_ALLOW_UNFREE=1 nix-shell --impure -p storcli --command \
  'sudo storcli /c0 show personality'

# Dump the full PD list and find the row matching sdX's serial. The
# output is long — capture it to a file.
NIXPKGS_ALLOW_UNFREE=1 nix-shell --impure -p storcli --command \
  'sudo storcli /c0/eall/sall show all' | sudo tee /tmp/storcli-pds.txt >/dev/null
grep -B1 -A2 "SN = <sdX-serial>" /tmp/storcli-pds.txt

# Blink the locate LED. Replace eN/sM with the enclosure/slot found above.
NIXPKGS_ALLOW_UNFREE=1 nix-shell --impure -p storcli --command \
  'sudo storcli /c0/eN/sM start locate'

# Stop after identification.
NIXPKGS_ALLOW_UNFREE=1 nix-shell --impure -p storcli --command \
  'sudo storcli /c0/eN/sM stop locate'
```

If `Current Personality` is `HBA`, `start locate` returns:

```
Status = Failure
Description = Start Drive Locate Failed.
…
ErrCd 255 — Operation not allowed.
```

Broadcom's 3108 firmware does not proxy SES locate to JBOD drives
behind a SAS expander in HBA personality, and `start locate force` is
not a valid token. Switching personality requires a reboot and
re-imports every JBOD, so it is not worth doing just to blink a LED.
Fall back to Method 2.

**Method 2 — Activity-LED trick (works regardless of personality).**

Pound the failing disk with sequential reads. Its activity LED blinks
constantly while every other caddy stays quiet. Safe to run against
the raw block device once A9.1 has detached the FS layer.

```bash
while true; do
  sudo dd if=/dev/sdX of=/dev/null bs=1M count=2000 iflag=direct status=none
done
```

`iflag=direct` bypasses the page cache so every loop iteration actually
hits the platter. Ctrl-C when you have identified the blinking caddy.
This is what worked in the May 2026 retirement.

**Method 3 — Physical-position counting (fallback).**

`storcli /c0/eall/sall show all` prints slots in physical order
starting at slot 0. Cross-reference the failing disk's model and
serial against the neighbouring slots to locate it visually. In the
May 2026 example, the chassis held three NETAPP X377 drives in
adjacent slots 0/1/2, with the failing one in slot 1 (the middle of
the three):

| Slot | Linux name | Model | Serial |
|------|-----------|-------|--------|
| s0   | sdf       | NETAPP X377_HLBRE10TA07 | 7PHSNSNG |
| s1   | sda       | NETAPP X377_HLBRE10TA07 | 7PHSPJ7G (failing) |
| s2   | sde       | NETAPP X377_HLBRE10TA07 | 7PHSNJKG |
| s3   | sdc       | WDC WD101EMAZ | VCH3BK7P |
| …    | …         | … | … |

#### A9.3 Pull the drive

Hot-pull is supported on the BP13G+EXP backplane. Pull the caddy you
identified, then verify the kernel released the device:

```bash
ls /dev/sdX 2>&1            # expect "No such file or directory"
lsblk | grep "^sdX " || echo "(gone)"
```

The slot will also disappear from `storcli /c0/e32/sM show` once the
drive is out.

#### A9.4 Restart anything still down

If you stopped any services manually in A2 that the rebuild did not
restart (for example if you `disable`d them rather than just
`stop`ped), start them now. Likewise restart any timers you stopped
post-rebuild for the manual sync window in A8:

```bash
sudo systemctl start \
  backup.timer snapraid-scrub.timer \
  restic-backups-config.timer restic-backups-matteo.timer \
  restic-backups-debora.timer restic-backups-fabrizio.timer \
  nextcloud-cron.timer nextcloud-scan-external.timer
```

#### A9.5 Update the diskpool handbook

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

Same as A2 — in particular, `backup.timer` must be stopped so it
does not run `snapraid sync` while the array is in a degraded state.

Note: if Phase B3 requires a `nixos-rebuild switch` (you generated a
new LUKS UUID instead of reusing the existing one), the switch
re-arms every stopped timer. Re-run the `systemctl stop ...` from A2
immediately after the rebuild and before starting B4. See the
Troubleshooting section for why `systemctl mask` is not an option on
NixOS-managed units.

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

Restart timers and application services as in A9.

---

## Troubleshooting

### `systemctl mask` does not work on NixOS-managed units

NixOS materialises every unit as a symlink at
`/etc/systemd/system/<unit>` pointing into `/nix/store`. Plain
`systemctl mask` tries to overwrite that path with `/dev/null` and
fails because the file already exists. `systemctl mask --runtime`
appears to succeed (it places `/run/systemd/system/<unit>` →
`/dev/null`) but is silently ignored at runtime: systemd's unit-file
search order puts `/etc/systemd/system` *before* `/run/systemd/system`,
so the real `/etc/` unit wins. `systemctl list-timers` continues to
show the timer armed, and `systemctl show -p LoadState` returns
`loaded` (not `masked`) with `FragmentPath` pointing into `/etc/`.

**Use `systemctl stop` to disarm a NixOS-managed timer instead.**
Stopping disarms the timer and makes its `NEXT` column show `-`. It
will stay stopped until something triggers a re-arm. The two
practical re-arm triggers in this procedure are:

- `nixos-rebuild switch` — the activation script reloads systemd and
  brings enabled timers back to their armed state. See A7's
  "What `nixos-rebuild switch` does automatically" subsection.
- An explicit `systemctl start <timer>`.

If you need a timer to stay disabled past a `nixos-rebuild switch`,
either re-run `systemctl stop` immediately after the rebuild, or
disable the timer in the nix module itself (more invasive, but
survives rebuilds and reboots).

### `snapraid sync` fails: "Error decoding … at offset N"

Full message:

```
Error decoding '/mnt/diskX/snapraid.content' at offset N
The CRC of the file is correct!
Disk 'dN' with uuid '<uuid>' not present in the configuration file!
If you have removed it from the configuration file, please restore it
```

The "Error decoding at offset N" wording is misleading — the file is
intact (note "The CRC of the file is correct"). The real complaint
is the follow-up line: SnapRAID's content file still references a
disk that no longer appears in the config. `--force-zero` alone (the
default in `backup.nix`) is not enough to proceed. Fix this with the
temp-config workaround in [Phase A8](#a8-re-sync-snapraid-against-the-new-layout)
— it's a one-time operation per disk removal, after which the
nix-managed config works on its own.

### Mergerfs xattr change reverted mid-drain

A service restart or reboot reapplies the nix-defined branch list,
which re-introduces the failing disk. The drain rsyncs will then start
routing files back onto it.

Fix: stop, re-apply `setfattr` from A3, and restart the rsync.

If you want belt-and-braces, do the nix-side edit from A7 *before*
starting the drain — the rebuild then makes the branch change
persistent. The trade-off is you cannot fall back cleanly to the
original 9-disk layout without another rebuild.

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

---

## Related documents

- [Diskpool Handbook](diskpool-handbook.md) — steady-state layout
- [Paperless-ngx Recovery](paperless-ngx-recovery.md)
- `hosts/Nexus/services/backup.nix` — canonical service list
- `hosts/Nexus/hardware-extra.nix` — LUKS, fileSystems, mergerfs mount
- `hosts/Nexus/snapraid.nix` — SnapRAID configuration

# BrightFalls Install Handbook

Fresh install of BrightFalls: single 4 TB NVMe, one LUKS2 container
(AES-256-XTS, argon2id 4 GB) holding LVM VG `brightfalls` — root / home /
swap / games, all ext4. One passphrase unlocks everything; the initrd runs
SSH on port 2222 for remote unlock. Layout: `hosts/Brightfalls/disko.nix`.

Install from the [InstallerISO](../../README.md#installeriso--custom-install-media)
— it ships disko, the private attic cache (token baked in), and the
`ssh nexus` alias.

> The flake refs below fetch from GitHub — push the branch first, or
> substitute a local clone path.

## 1. Before the wipe

No raw `/home` backup exists on Nexus (only Nextcloud-synced data), so
stash anything worth keeping while the old system still boots:

```bash
rsync -a ~/important-stuff/ nexus:/diskpool/pc-backups/brightfalls/
```

On Nexus (once): make sure `matteo` has a password (`passwd`) — the
installer restores over password SSH, allowed from the HOME VLAN only
(`hosts/Nexus/services/openssh.nix`).

## 2. Install (booted from the InstallerISO)

```bash
# Stage the LUKS passphrase (used by luksFormat only, never at boot)
echo -n '<passphrase>' > /tmp/luks.password

# Partition, format, mount — WIPES THE DISK
sudo disko --mode destroy,format,mount \
  --flake github:matteo-pacini/nixos-configs#BrightFalls

# Pre-generate the initrd SSH host key (remote unlock)
sudo mkdir -p /mnt/etc/secrets/initrd
sudo ssh-keygen -t ed25519 -N "" -f /mnt/etc/secrets/initrd/ssh_host_ed25519_key

# Install
sudo nixos-install --flake github:matteo-pacini/nixos-configs#BrightFalls

# Restore stashed files (password prompt)
rsync -a nexus:/diskpool/pc-backups/brightfalls/ /mnt/home/matteo/restore/
```

## 3. After first boot

- **Re-key agenix**: the fresh install has a new host key. Put the new
  `/etc/ssh/ssh_host_ed25519_key.pub` into `secrets/secrets.nix`, then
  `cd secrets && agenix --rekey -i <valid identity>` — until then
  `brightfalls/attic-netrc.age` won't decrypt and the attic cache is
  substituter-only for other hosts' pushes.
- **Stale EFI entries**: `efibootmgr` — delete leftovers (e.g. an old
  Windows Boot Manager) with `efibootmgr -b XXXX -B`.
- **Verify**:
  - `lsblk -f` shows `cryptroot` → LVM → ext4
  - `cryptsetup luksDump /dev/nvme0n1p2` shows LUKS2, `aes-xts-plain64`,
    key 512 bits, `argon2id`
  - hibernate/resume round-trip
  - remote unlock: reboot, `ssh -p 2222 root@brightfalls`, answer the
    prompt via `systemd-tty-ask-password-agent`

## Resizing volumes later

```bash
sudo lvresize -L +100G brightfalls/games   # grow (online)
sudo resize2fs /dev/brightfalls/games

# shrink = offline for that LV: umount, resize2fs first, then lvresize
```

No `cryptsetup resize` ever needed — LVM lives inside the container.

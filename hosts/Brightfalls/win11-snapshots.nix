# Streaming Windows 11 partition snapshots to Nexus.
# No local staging: dd -> zstd -> ssh (create), ssh -> zstd -> dd (restore).
{ pkgs, ... }:
let
  # Windows partition (p6) on the 4TB Crucial — see disko.nix
  device = "/dev/disk/by-id/nvme-CT4000P310SSD8_25184FF48CDC-part6";
  mountPoint = "/mnt/windows";
  automountUnit = "mnt-windows.automount"; # systemd-escape -p ${mountPoint}
  remote = "nexus";
  remoteDir = "/diskpool/win11-snapshots";

  # dd against a mounted partition reads/writes an inconsistent filesystem.
  # Stop the automount first or any access during dd remounts it.
  ensureUnmounted = ''
    if systemctl is-active --quiet ${automountUnit}; then
      echo "stopping ${automountUnit} (restart with: systemctl start ${automountUnit})" >&2
      sudo systemctl stop ${automountUnit}
    fi
    if findmnt -rn -S ${device} >/dev/null; then
      echo "unmounting ${device}" >&2
      sudo umount ${device}
    fi
  '';

  win11-snapshot-create = pkgs.writeShellScriptBin "win11-snapshot-create" ''
    set -euo pipefail

    NAME=''${1:-}
    if [[ -z "$NAME" ]]; then
      echo "usage: win11-snapshot-create NAME" >&2
      exit 1
    fi
    if [[ ! "$NAME" =~ ^[A-Za-z0-9._-]+$ ]]; then
      echo "error: NAME must match [A-Za-z0-9._-]+" >&2
      exit 1
    fi
    FILE="${remoteDir}/$NAME.img.zst"

    if ssh ${remote} "test -e \"$FILE\""; then
      echo "error: snapshot '$NAME' already exists on ${remote}" >&2
      exit 1
    fi

    sudo -v
    ${ensureUnmounted}
    SIZE=$(sudo blockdev --getsize64 ${device})

    # .partial then rename: an interrupted transfer never looks like a valid snapshot
    sudo dd if=${device} bs=64M status=none \
      | ${pkgs.pv}/bin/pv -s "$SIZE" \
      | ${pkgs.zstd}/bin/zstd -q -T0 -6 --long=27 \
      | ssh -o Compression=no ${remote} "cat > \"$FILE.partial\" && mv \"$FILE.partial\" \"$FILE\""

    echo "snapshot '$NAME' created"
  '';

  win11-snapshot-list = pkgs.writeShellScriptBin "win11-snapshot-list" ''
    set -euo pipefail
    ssh ${remote} "ls -l --block-size=M ${remoteDir}" | ${pkgs.gawk}/bin/awk '
      sub(/\.img\.zst$/, "", $NF) { printf "%-40s %8s  %s %s %s\n", $NF, $5, $6, $7, $8 }
    '
  '';

  win11-snapshot-restore = pkgs.writeShellScriptBin "win11-snapshot-restore" ''
    set -euo pipefail

    list_snapshots() {
      echo "available snapshots:" >&2
      ssh ${remote} "ls -1 ${remoteDir}" 2>/dev/null | sed -n 's/\.img\.zst$//p' >&2 || true
    }

    NAME=''${1:-}
    if [[ -z "$NAME" ]]; then
      echo "usage: win11-snapshot-restore NAME" >&2
      list_snapshots
      exit 1
    fi
    if [[ ! "$NAME" =~ ^[A-Za-z0-9._-]+$ ]]; then
      echo "error: NAME must match [A-Za-z0-9._-]+" >&2
      exit 1
    fi
    FILE="${remoteDir}/$NAME.img.zst"

    if ! ssh ${remote} "test -e \"$FILE\""; then
      echo "error: snapshot '$NAME' not found on ${remote}" >&2
      list_snapshots
      exit 1
    fi

    echo "WARNING: this overwrites the Windows partition (${device}) with snapshot '$NAME'."
    read -r -p "Type the snapshot name to confirm: " REPLY
    if [[ "$REPLY" != "$NAME" ]]; then
      echo "aborted" >&2
      exit 1
    fi

    sudo -v
    ${ensureUnmounted}
    SIZE=$(ssh ${remote} "stat -c %s \"$FILE\"")

    ssh -o Compression=no ${remote} "cat \"$FILE\"" \
      | ${pkgs.pv}/bin/pv -s "$SIZE" \
      | ${pkgs.zstd}/bin/zstd -q -d --long=27 \
      | sudo dd of=${device} bs=64M conv=fsync status=none

    echo "snapshot '$NAME' restored"
  '';

  win11-snapshot-delete = pkgs.writeShellScriptBin "win11-snapshot-delete" ''
    set -euo pipefail

    list_snapshots() {
      echo "available snapshots:" >&2
      ssh ${remote} "ls -1 ${remoteDir}" 2>/dev/null | sed -n 's/\.img\.zst$//p' >&2 || true
    }

    NAME=''${1:-}
    if [[ -z "$NAME" ]]; then
      echo "usage: win11-snapshot-delete NAME" >&2
      list_snapshots
      exit 1
    fi
    if [[ ! "$NAME" =~ ^[A-Za-z0-9._-]+$ ]]; then
      echo "error: NAME must match [A-Za-z0-9._-]+" >&2
      exit 1
    fi
    FILE="${remoteDir}/$NAME.img.zst"

    if ! ssh ${remote} "test -e \"$FILE\""; then
      echo "error: snapshot '$NAME' not found on ${remote}" >&2
      list_snapshots
      exit 1
    fi

    echo "WARNING: this permanently deletes snapshot '$NAME' from ${remote}."
    read -r -p "Type the snapshot name to confirm: " REPLY
    if [[ "$REPLY" != "$NAME" ]]; then
      echo "aborted" >&2
      exit 1
    fi

    ssh ${remote} "rm \"$FILE\""
    echo "snapshot '$NAME' deleted"
  '';
in
{
  # In-kernel ntfs3 driver. Fast Startup is disabled on the Windows side, so
  # the volume is normally clean; lazy mount + nofail still keep a dirty
  # volume (e.g. Windows crash) from failing the boot.
  fileSystems.${mountPoint} = {
    inherit device;
    fsType = "ntfs3";
    noCheck = true; # no fsck.ntfs3 exists; real repair is chkdsk from Windows
    options = [
      "uid=1000"
      "gid=100"
      "windows_names" # forbid filenames Windows can't handle
      "iocharset=utf8"
      "nofail"
      "noauto"
      "x-systemd.automount"
      "x-systemd.idle-timeout=600"
    ];
  };

  environment.systemPackages = [
    pkgs.ntfs3g # ntfsfix, for clearing the dirty flag after a Windows crash
    win11-snapshot-create
    win11-snapshot-list
    win11-snapshot-restore
    win11-snapshot-delete
  ];
}

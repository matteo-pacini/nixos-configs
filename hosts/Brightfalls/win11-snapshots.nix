# Streaming Windows 11 partition snapshots to Nexus.
# No local staging: dd -> zstd -> ssh (create), ssh -> zstd -> dd (restore).
{ pkgs, ... }:
let
  # Windows partition (p6) on the 4TB Crucial — see disko.nix
  device = "/dev/disk/by-id/nvme-CT4000P310SSD8_25184FF48CDC-part6";
  remote = "nexus";
  remoteDir = "/diskpool/win11-snapshots";

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
    SIZE=$(ssh ${remote} "stat -c %s \"$FILE\"")

    ssh -o Compression=no ${remote} "cat \"$FILE\"" \
      | ${pkgs.pv}/bin/pv -s "$SIZE" \
      | ${pkgs.zstd}/bin/zstd -q -d --long=27 \
      | sudo dd of=${device} bs=64M conv=fsync status=none

    echo "snapshot '$NAME' restored"
  '';
in
{
  environment.systemPackages = [
    win11-snapshot-create
    win11-snapshot-list
    win11-snapshot-restore
  ];
}

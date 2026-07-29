{ pkgs, ... }:
let
  # Spin a pool HDD down after this many seconds idle. Conservative on
  # purpose: too-aggressive spindown trades watts for load/unload cycles,
  # which matters for the enterprise He10s.
  idleSeconds = 1800;

  # hd-idle has no NixOS module (package only, v1.22), so hand-roll the unit.
  #
  # The disk set is enumerated at start rather than hardcoded: Nexus swaps
  # pool disks periodically, and the physical serials live nowhere in the
  # repo (data disks are addressed by LUKS mapper name, parity by fs UUID).
  # Rotational==1 selects exactly the 11 pool HDDs and never the SSDs
  # (root + mdadm mirror are non-rotational).
  #
  # Command API is per-disk because the pool is mixed and all drives sit
  # behind a SAS HBA (lsblk reports no TRAN): the two He10 SAS drives take
  # SCSI START STOP UNIT (-c scsi), the WD SATA drives take ATA STANDBY
  # (-c ata). A libata (SATA) disk exposes an /dev/disk/by-id/ata-* alias;
  # a SAS disk does not — that presence is the transport signal.
  #
  # SAS drives additionally need -p 3 (STANDBY power condition). hd-idle's
  # default power_condition=0 issues a plain STOP UNIT, which parks a SAS
  # LU in a state it cannot leave without an explicit START UNIT: every
  # subsequent read returns NOT READY 04/02, which this HBA (megaraid_sas,
  # allow_restart=0 on SAS end devices) surfaces as EIO rather than
  # recovering. That killed the ext4 on disk0+disk2 on 2026-07-28. A power
  # condition auto-transitions back to active inside the drive on media
  # access — measured ~10s to first read, with nothing in the kernel log.
  spindown = pkgs.writeShellScript "hd-idle-spindown" ''
    set -euo pipefail

    # -i 0 default: never spin down anything not explicitly listed below.
    args=(-i 0)

    for dev in /sys/block/sd*; do
      name=''${dev##*/}
      [ -r "$dev/queue/rotational" ] || continue
      [ "$(cat "$dev/queue/rotational")" = 1 ] || continue

      id=""
      ctype="scsi"
      # SATA: prefer the stable ata-* alias and use the ATA command API.
      for l in /dev/disk/by-id/ata-*; do
        [ -e "$l" ] || continue
        case "$l" in *-part*) continue ;; esac
        if [ "$(readlink -f "$l")" = "/dev/$name" ]; then
          id="$l"
          ctype="ata"
          break
        fi
      done
      # SAS (no ata-* alias): fall back to the wwn-* alias, keep SCSI API.
      if [ -z "$id" ]; then
        for l in /dev/disk/by-id/wwn-*; do
          [ -e "$l" ] || continue
          case "$l" in *-part*) continue ;; esac
          if [ "$(readlink -f "$l")" = "/dev/$name" ]; then
            id="$l"
            break
          fi
        done
      fi
      [ -n "$id" ] || id="/dev/$name"

      pc=()
      if [ "$ctype" = scsi ]; then
        pc=(-p 3)
      fi
      args+=(-a "$id" -c "$ctype" "''${pc[@]}" -i ${toString idleSeconds})
    done

    echo "hd-idle: ''${args[*]}"
    exec ${pkgs.hd-idle}/bin/hd-idle "''${args[@]}"
  '';

  # drive-status: non-waking spin state of every pool HDD (needs root for the
  # hdparm/sdparm ioctls). Same enumeration + SAS/SATA split as the daemon.
  driveStatus = pkgs.writeShellApplication {
    name = "drive-status";
    runtimeInputs = with pkgs; [
      hdparm
      sdparm
      gawk
    ];
    text = ''
      if [ "$(id -u)" -ne 0 ]; then
        echo "drive-status: needs root — run: sudo drive-status" >&2
        exit 1
      fi
      for dev in /sys/block/sd*; do
        name=''${dev##*/}
        [ "$(cat "$dev/queue/rotational" 2>/dev/null)" = 1 ] || continue
        id=""
        type="scsi"
        for l in /dev/disk/by-id/ata-*; do
          case "$l" in *-part*) continue ;; esac
          [ "$(readlink -f "$l")" = "/dev/$name" ] && { id="$l"; type="ata"; break; }
        done
        if [ -z "$id" ]; then
          for l in /dev/disk/by-id/wwn-*; do
            case "$l" in *-part*) continue ;; esac
            [ "$(readlink -f "$l")" = "/dev/$name" ] && id="$l"
          done
        fi
        [ -n "$id" ] || id="/dev/$name"
        if [ "$type" = ata ]; then
          state=$(hdparm -C "$id" | awk -F'is: *' '/drive state/{print $2}')
        # FIXME: only detects a *stopped* SAS LU (NOT READY 04/02). Since the
        # daemon switched to -p 3, a parked drive sits in a STANDBY power
        # condition and answers sense normally, so it reads as "active" here
        # even with the motor down. Needs a real power-condition probe.
        elif sdparm --command=sense "$id" 2>&1 | grep -qiE 'not ready|initializing'; then
          state="standby (stopped)"
        else
          state="active"
        fi
        printf '%-4s %-5s %-42s %s\n' "$name" "$type" "''${id##*/}" "$state"
      done
    '';
  };
in
{
  environment.systemPackages = [ driveStatus ];

  systemd.services.hd-idle = {
    description = "Spin down idle pool HDDs after ${toString idleSeconds}s";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = spindown;
      Restart = "on-failure";
      RestartSec = 30;
    };
  };
}

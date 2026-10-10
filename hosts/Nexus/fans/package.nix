# Dell PowerEdge R730xd iDRAC fan control, shared by the CLI and Home Assistant.
#
# State lives in /run/nexus-fans (see ./default.nix):
#   lock      held shared by every with-fans run, for as long as its command lives
#   state     serialises baseline writes against restores
#   baseline  "auto" or a duty; what the fans return to when no run is active
#   override  duty of the most recent with-fans run; only meaningful while lock is held
{
  ipmitool,
  util-linux,
  coreutils,
  writeShellApplication,
  symlinkJoin,
}:
let
  dir = "/run/nexus-fans";
  runtimeInputs = [
    ipmitool
    util-linux
    coreutils
  ];

  # The iDRAC OEM opcodes are write-only: the BMC never reports duty or mode
  # back, so the baseline file is the only record of what was requested.
  common = ''
    dir=${dir}

    # Prints the duty as a plain decimal, or fails if it is outside 20-100.
    # Floor of 20: lower duties let the chassis overheat under load.
    duty() {
      [[ "$1" =~ ^[0-9]+$ ]] || return 1
      local d=$((10#$1))
      ((d >= 20 && d <= 100)) || return 1
      echo "$d"
    }

    apply() {
      if [ "$1" = auto ]; then
        ipmitool raw 0x30 0x30 0x01 0x01 >/dev/null
      else
        ipmitool raw 0x30 0x30 0x01 0x00 >/dev/null
        ipmitool raw 0x30 0x30 0x02 0xff "$(printf '0x%02x' "$1")" >/dev/null
      fi
    }
  '';

  restore = writeShellApplication {
    name = "nexus-fans-restore";
    inherit runtimeInputs;
    text = common + ''
      exec 8<"$dir/lock"
      flock -x 8
      exec 9<"$dir/state"
      flock 9

      baseline=$(cat "$dir/baseline")
      if [ "$baseline" != auto ]; then
        baseline=$(duty "$baseline") || baseline=auto
      fi
      apply "$baseline"
      : >"$dir/override"

      # Release the run lock before the state lock: a `fans` call queued on
      # the state lock must find the run lock free, or its baseline is lost.
      exec 8<&-
      exec 9<&-
    '';
  };

  fans = writeShellApplication {
    name = "fans";
    inherit runtimeInputs;
    text = common + ''
      usage() {
        echo "usage: fans <20-100|auto>" >&2
        echo "Sets the baseline duty. While a with-fans run is active it applies when the last run exits." >&2
        exit 2
      }

      [ $# -eq 1 ] || usage
      if [ "$1" = auto ]; then
        target=auto
      else
        target=$(duty "$1") || usage
      fi

      exec 9<"$dir/state"
      flock 9
      echo "$target" >"$dir/baseline"
      exec 8<"$dir/lock"
      if flock -n -x 8; then
        apply "$target"
      fi
    '';
  };

  withFans = writeShellApplication {
    name = "with-fans";
    runtimeInputs = runtimeInputs ++ [ restore ];
    text = common + ''
      usage() {
        echo "usage: with-fans <20-100> [--] CMD [ARGS...]" >&2
        echo "Holds the fans at the given duty while CMD runs, then restores the baseline (see: fans)." >&2
        exit 2
      }

      [ $# -ge 1 ] || usage
      d=$(duty "$1") || usage
      shift
      [ "''${1-}" = -- ] && shift
      [ $# -ge 1 ] || usage

      # CMD inherits fd 8 through exec, so the shared lock lives exactly as
      # long as CMD does, however it ends (including SIGKILL).
      exec 8<"$dir/lock"
      flock -s 8
      echo "$d" >"$dir/override"
      apply "$d"

      # The restorer must not inherit fd 8, or its exclusive lock waits on itself.
      setsid -f nexus-fans-restore 8<&- </dev/null >/dev/null 2>&1

      exec "$@"
    '';
  };

  status = writeShellApplication {
    name = "nexus-fans-status";
    inherit runtimeInputs;
    text = ''
      dir=${dir}
      exec 8<"$dir/lock"
      if flock -n -x 8; then
        echo off
      else
        cat "$dir/override"
      fi
    '';
  };
in
symlinkJoin {
  name = "nexus-fans";
  paths = [
    fans
    withFans
    restore
    status
  ];
}

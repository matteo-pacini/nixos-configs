# comin-deploy: releases the generation comin holds for confirmation
# (custom.autoDeploy.confirm), and keeps the host's deploy mode.
#
#   comin-deploy boot|switch [generation]  deploy the waiting generation; with
#                                          a generation uuid, only if it is
#                                          still the one waiting
#   comin-deploy auto                      what the timer runs: deploy the
#                                          waiting generation as the mode says
#   comin-deploy mode [manual|boot|switch] print or set the mode
#
# The mode file holds manual (the default: wait for someone), boot or switch.
# comin's own operation is branchOperation; a switch on a `boot` host stages
# with boot first (so the boot entry exists), then has comin resubmit the same
# deployment with switch. A `switch` host (Darwin) cannot boot.
{
  pkgs,
  comin,
  branchOperation,
  modeFile,
}:
pkgs.writeShellApplication {
  name = "comin-deploy";
  runtimeInputs = [
    comin
    pkgs.coreutils
    pkgs.gawk
    pkgs.gnused
  ];
  text = ''
    mode_file=${pkgs.lib.escapeShellArg modeFile}
    branch_operation=${branchOperation}
    if [[ $branch_operation == boot ]]; then modes="manual boot switch"; else modes="manual switch"; fi

    waiting() { comin confirmation show | sed -n 's/^Confirmation needed for deploying: //p'; }

    # Waits until comin's latest finished deployment is <generation> with
    # <operation>; fails if that deployment failed. A running deployment has
    # no end time yet, so it never shows as the latest.
    wait_for() {
      local gen=$1 op=$2 line
      for _ in $(seq 600); do
        line=$(comin deployment latest | awk '
          $1 == "status" { st = $2 } $1 == "operation" { op = $2 }
          $1 == "generation" && $2 == "uuid" { gen = $3 }
          END { print gen, op, st }')
        read -r g o s <<<"$line"
        if [[ $g == "$gen" && $o == "$op" ]]; then
          case $s in
            done) return 0 ;;
            failed) echo "comin: the $op deployment failed; see comin status" >&2; return 1 ;;
          esac
        fi
        sleep 3
      done
      echo "comin: gave up waiting for the $op deployment after 30 minutes" >&2
      return 1
    }

    deploy() {
      local target=$1 expected=''${2:-} gen
      if [[ $target == boot && $branch_operation != boot ]]; then
        echo "This host can only switch." >&2; return 1
      fi
      gen=$(waiting)
      if [[ -z $gen ]]; then echo "Nothing is waiting for confirmation."; return 0; fi
      if [[ -n $expected && $gen != "$expected" ]]; then
        echo "A newer generation ($gen) is waiting now; refresh and check it first." >&2; return 1
      fi
      echo "Deploying generation $gen with $branch_operation…"
      comin confirmation accept >/dev/null
      wait_for "$gen" "$branch_operation"
      if [[ $target == switch && $branch_operation == boot ]]; then
        echo "Staged. Switching to it now…"
        comin deployment submit-latest --operation switch
        wait_for "$gen" switch
      fi
      echo "Done: $target."
    }

    current_mode() {
      local m
      m=$(cat "$mode_file" 2>/dev/null || true)
      case " $modes " in *" $m "*) echo "$m" ;; *) echo manual ;; esac
    }

    case "''${1:-}" in
      boot | switch) deploy "$@" ;;
      auto)
        m=$(current_mode)
        if [[ $m != manual && -n $(waiting) ]]; then deploy "$m"; fi
        ;;
      mode)
        if [[ -z ''${2:-} ]]; then current_mode; exit 0; fi
        case " $modes " in
          *" $2 "*) printf '%s\n' "$2" >"$mode_file" ;;
          *) echo "mode must be one of: $modes" >&2; exit 1 ;;
        esac
        ;;
      *) echo "usage: comin-deploy boot|switch [generation] | auto | mode [$modes]" >&2; exit 2 ;;
    esac
  '';
}

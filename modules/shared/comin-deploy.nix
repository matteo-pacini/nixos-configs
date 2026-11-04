# comin-deploy: the one controller of comin's deploy confirmation
# (custom.autoDeploy.confirm), used by the herdr Deploy panel and the timer.
#
#   comin-deploy boot [generation]    deploy the held generation with boot
#   comin-deploy switch [generation]  make the newest system live: the held
#                                     generation, or the one staged for boot
#   comin-deploy auto                 what the timer runs (see below)
#   comin-deploy mode [manual|boot|switch]  print or set the mode
#
# With a generation uuid, boot and switch act only on that generation, so a
# newer one that arrived meanwhile is not deployed unseen.
#
# A switch on a `boot` host stages with boot first (so the boot entry
# exists), then has comin resubmit that deployment with switch. comin turns a
# switch into a boot when the new system changes a switch-inhibitor; that is
# reported, never forced. A `switch` host (Darwin) cannot boot.
#
# auto releases a held system that equals the staged one in every mode (comin
# holds those: commits that leave this host alone, the same commit again after
# a restart), and otherwise deploys the held generation as the mode says.
#
# The mode file holds manual (the default: wait for someone), boot or switch.
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
    pkgs.jq
  ];
  text = ''
    mode_file=${pkgs.lib.escapeShellArg modeFile}
    branch_operation=${branchOperation}
    if [[ $branch_operation == boot ]]; then modes="manual boot switch"; else modes="manual switch"; fi

    # comin exits on purpose after a deployment that changes its own unit, and
    # its CLI can block: every call has a timeout, and status is retried for a
    # minute while comin comes back.
    status() {
      local out
      for _ in $(seq 20); do
        if out=$(timeout 20 comin status --json 2>/dev/null); then
          S=$out
          return 0
        fi
        sleep 3
      done
      echo "comin did not answer for a minute; check comin status." >&2
      return 1
    }
    q() { jq -r "$1" <<<"$S"; }

    held() { q '.deploy_confirmer.submitted // ""'; }
    # shellcheck disable=SC2016 # $u is jq, not shell
    held_out() { q '.deploy_confirmer.submitted as $u | first(.store.generations[]? | select(.uuid == $u) | .out_path) // ""'; }
    # The system comin last deployed successfully: what boots next.
    staged() { q '[.store.deployments[]? | select(.status == "done")] | max_by(.ended_at) | .generation.out_path // ""'; }
    busy() { [[ $(q '(.deployer.is_deploying // false) or (.deployer.generation_to_deploy != null)') == true ]]; }
    suspended() { [[ $(q '(.is_suspended // false) or (.deployer.is_suspended // false)') == true ]]; }
    dep() { q ".deployer.deployment.$1 // \"\""; }

    # Waits until comin's current deployment is a finished one other than
    # <uuid>. Between a confirmation and the deployer picking it up, comin
    # looks idle with the old deployment, so only a new uuid counts.
    wait_new() {
      local prev=$1
      for _ in $(seq 600); do
        status || return 1
        if [[ $(dep uuid) != "$prev" ]] && ! busy; then
          case $(dep status) in done | failed) return 0 ;; esac
        fi
        sleep 3
      done
      echo "Gave up after 30 minutes; check comin status." >&2
      return 1
    }

    # Says what the deployment comin just finished did; fails if it failed.
    report() {
      local want=$1
      if [[ $(dep status) == failed ]]; then
        echo "The deployment failed: $(dep error_msg)" >&2
        return 1
      fi
      if [[ $want == switch && $(dep operation) == boot ]]; then
        echo "comin staged it for the next boot instead of switching: the new system changes a switch-inhibitor"
        echo "($(q '.deployer.deployment.current_inhibitors // [] | join(", ")') → $(q '.deployer.deployment.new_inhibitors // [] | join(", ")'))."
        echo "Reboot to run it."
        return 2
      fi
      echo "Done: $(dep operation) of $(q '.deployer.deployment.generation.selected_commit_id // "" | .[0:7]')."
    }

    # Resubmits comin's latest deployment, a finished boot of the staged
    # system, with switch.
    switch_staged() {
      local prev
      prev=$(dep uuid)
      echo "Switching to the staged system…"
      timeout 20 comin deployment submit-latest --operation switch
      wait_new "$prev" || return 1
      report switch
    }

    deploy() {
      local target=$1 expected=''${2:-} gen prev rc prev_seen
      if [[ $target == boot && $branch_operation != boot ]]; then
        echo "This host can only switch." >&2; return 1
      fi
      status || return 1
      prev_seen=$(dep uuid)
      if suspended; then echo "comin is suspended; run comin resume first." >&2; return 1; fi

      gen=$(held)
      if [[ -n $gen ]]; then
        if [[ -n $expected && $gen != "$expected" ]]; then
          echo "A newer generation ($gen) is held now; check it first." >&2; return 1
        fi
        prev=$(dep uuid)
        echo "Deploying generation $gen with $branch_operation…"
        timeout 20 comin confirmation accept >/dev/null
        wait_new "$prev" || return 1
        if [[ $(dep generation.uuid) != "$gen" ]]; then
          echo "comin deployed $(dep generation.uuid), not $gen; check comin status." >&2; return 1
        fi
      elif busy; then
        # Already released (by the timer, or another click): follow it.
        echo "comin is already deploying; following it…"
        wait_new "" || return 1
      elif [[ $target == boot ]]; then
        echo "Nothing is held."; return 0
      fi

      if [[ -n $gen ]] || [[ $(dep uuid) != "$prev_seen" ]]; then
        rc=0
        report "$branch_operation" || rc=$?
        [[ $rc == 0 ]] || return $rc
      fi
      if [[ -n $expected && $(dep generation.uuid) != "$expected" && -z $gen ]]; then
        echo "Generation $expected is no longer the latest; check the panel." >&2; return 1
      fi
      if [[ $target == switch && $branch_operation == boot ]]; then
        if [[ $(dep operation) == boot && $(dep status) == "done" \
              && $(dep generation.out_path) != "$(readlink -f /run/current-system)" ]]; then
          switch_staged
        else
          echo "Already running the staged system."
        fi
      fi
    }

    current_mode() {
      local m
      m=$(cat "$mode_file" 2>/dev/null || true)
      case " $modes " in *" $m "*) echo "$m" ;; *) echo manual ;; esac
    }

    case "''${1:-}" in
      boot | switch) deploy "$@" ;;
      auto)
        status
        gen=$(held)
        [[ -n $gen ]] || exit 0
        suspended && exit 0
        busy && exit 0
        out=$(held_out)
        if [[ -n $out && $out == "$(staged)" ]]; then
          echo "Releasing $gen: same system as the staged one."
          timeout 20 comin confirmation accept >/dev/null
          exit 0
        fi
        m=$(current_mode)
        [[ $m == manual ]] || deploy "$m" "$gen"
        ;;
      mode)
        if [[ -z ''${2:-} ]]; then current_mode; exit 0; fi
        case " $modes " in
          *" $2 "*)
            # Group-writable, so any wheel/admin member can change it later.
            (umask 002 && printf '%s\n' "$2" >"$mode_file.tmp") \
              && chgrp "$(stat -c %G "$(dirname "$mode_file")")" "$mode_file.tmp" \
              && mv -f "$mode_file.tmp" "$mode_file"
            ;;
          *) echo "mode must be one of: $modes" >&2; exit 1 ;;
        esac
        ;;
      *) echo "usage: comin-deploy boot|switch [generation] | auto | mode [$modes]" >&2; exit 2 ;;
    esac
  '';
}

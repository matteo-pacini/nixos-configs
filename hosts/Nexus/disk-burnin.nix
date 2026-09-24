{ pkgs, ... }:
let
  # Acceptance test for a drive before it joins the pool. Pool disks are
  # bought used (see the Changelog in docs/nexus/diskpool-handbook.md), and a
  # used drive's failure risk is front-loaded: it shows up under sustained
  # write load, not at idle. The window to act on that is the seller's return
  # period, so the test has to finish in days.
  #
  # The stages are separate commands because two of them run for ~19h and
  # ~28h. Run each under tmux; state carries between them through the report
  # files in /var/lib/disk-burnin.
  #
  # Deliberately not a systemd unit: it is destructive, run rarely, and wants
  # a human deciding which device it points at.
  burnin = pkgs.writeShellApplication {
    name = "disk-burnin";
    runtimeInputs = with pkgs; [
      smartmontools
      e2fsprogs # badblocks
      util-linux # lsblk
      systemd # systemctl, for the hd-idle interlock
      gawk
      gnugrep
      diffutils
      coreutils
    ];
    text = ''
      # errexit aborts silently; say where, so a failure is never mistaken for
      # a stage that produced no output.
      set -o errtrace
      trap 'echo "disk-burnin: aborted at line $LINENO: $BASH_COMMAND" >&2' ERR

      STAGE=''${1:-}
      DEV=''${2:-}
      OUTDIR=/var/lib/disk-burnin

      usage() {
        cat >&2 <<EOF
      usage: sudo disk-burnin <stage> /dev/sdX

      stages, in order:
        baseline   SMART snapshot before any stress          seconds
        longtest   drive-firmware full surface read          ~19h per 10TB
        burn       DESTRUCTIVE write-read of every sector    ~28h per 10TB
        verdict    diff counters against baseline, PASS/FAIL seconds

      Reports are kept in $OUTDIR/<serial>.*
      EOF
        exit 1
      }

      [ "$(id -u)" -eq 0 ] || { echo "disk-burnin: needs root" >&2; exit 1; }
      [ -n "$STAGE" ] && [ -b "$DEV" ] || usage

      # smartctl encodes findings in its exit status as a bitmask, not just
      # errors: bit 6 is "error log contains records", bit 7 is "a self-test
      # failed". Under writeShellApplication's `set -e` an unguarded call
      # would abort the script on precisely the drives this tool exists to
      # catch. Only bits 0-1 (usage error, device open failed) are fatal.
      #
      # -n never: report the power mode but never skip the command. hd-idle
      # parks pool disks, and the default would otherwise let a sleeping
      # drive answer with no data at all.
      smart() {
        local rc=0
        smartctl "$@" -n never "$DEV" || rc=$?
        # 141 is SIGPIPE: the reader (grep -q, awk '... exit') stopped once it
        # had its answer. Not a failure — and 141 & 3 would misread as one.
        [ "$rc" -eq 141 ] && return 0
        [ $((rc & 3)) -eq 0 ] || return "$rc"
        return 0
      }

      # SAS and SATA report the same physical facts under different names, and
      # SAS has no attribute table at all. Everything downstream branches here.
      if smart -i | grep -q 'Transport protocol.*SAS'; then
        TRANSPORT=sas
      else
        TRANSPORT=sata
      fi

      SERIAL=$(smart -i | awk -F': *' '/^Serial [Nn]umber/{print $2; exit}')
      [ -n "$SERIAL" ] || SERIAL=$(basename "$DEV")
      MODEL=$(smart -i | awk -F': *' '/^(Device Model|Product|Model Number)/{print $2; exit}')
      BASE="$OUTDIR/$SERIAL"
      mkdir -p "$OUTDIR"

      # A drive under acceptance test must be blank. A pool disk is GPT with
      # LUKS (data) or ext4 (parity) on the partition, so once its mapping is
      # closed the device row reads FSTYPE="" and only PTTYPE="gpt" marks it
      # as in use. Inspect the device's own row, not just children, and treat
      # a filesystem signature, partition table or mountpoint as
      # disqualifying.
      assert_unused() {
        local rows
        rows=$(lsblk -nPo NAME,FSTYPE,PTTYPE,MOUNTPOINT "$DEV")
        if [ "$(printf '%s\n' "$rows" | grep -c .)" -gt 1 ]; then
          echo "REFUSING: $DEV has child nodes — not a blank drive." >&2
          printf '%s\n' "$rows" >&2
          exit 1
        fi
        if printf '%s\n' "$rows" | grep -qE '(FSTYPE|PTTYPE|MOUNTPOINT)="[^"]+"'; then
          echo "REFUSING: $DEV carries a filesystem, partition table or mount." >&2
          printf '%s\n' "$rows" >&2
          exit 1
        fi
        if grep -q "$(basename "$DEV")" /proc/mounts; then
          echo "REFUSING: $DEV appears in /proc/mounts" >&2
          exit 1
        fi
      }

      poh() {
        if [ "$TRANSPORT" = sas ]; then
          smart -x | awk -F'hours:minutes *' \
            '/Accumulated power on time/ {split($2,a,":"); print a[1]+0; exit}'
        else
          smart -A | awk '$1==9 {print $10+0; exit}'
        fi
      }

      # Only counters that stay put on a healthy drive. Deliberately excludes
      # the SAS gigabytes-processed and ECC-invocation columns, which tick on
      # every read and would make the diff below fail every drive after a
      # 28h test; and excludes non-medium error count, which the hd-idle
      # STANDBY/START cycle increments through no fault of the media.
      counters() {
        if [ "$TRANSPORT" = sas ]; then
          printf 'grown_defects %s\n' "$(sas_grown_defects)"
          printf 'blocks_reassigned %s\n' "$(sas_reassigned)"
          printf 'uncorrected %s\n' "$(sas_uncorrected)"
        else
          smart -A | awk '$1 ~ /^(5|187|188|197|198|199)$/ {print $1, $2, $10}'
        fi
      }

      # Last column of each error-counter row is lifetime uncorrected errors:
      # the drive could not recover the data by any means. The SAS equivalent
      # of a pending sector.
      sas_uncorrected() {
        smart -x | awk '/^(read|write|verify):/ {s += $NF} END {print s+0}'
      }

      sas_grown_defects() {
        smart -x | awk -F': *' '/Elements in grown defect list/ {print $2+0; exit}'
      }

      sas_reassigned() {
        smart -x | awk -F'= *' '/Total new blocks reassigned/ {print $2+0; exit}'
      }

      # One parser for both transports. SAS rows end in a "[SK ASC ASQ]"
      # bracket group; strip it and the lifetime-hours column is the
      # second-to-last field on either format.
      selftest_rows() {
        smart -l selftest | grep -E '^#' | sed 's/\[[^]]*\]//'
      }

      header() {
        printf '%s  %s  serial %s  (%s)\n' "$DEV" "''${MODEL:-unknown}" "$SERIAL" "$TRANSPORT"
      }

      case "$STAGE" in
        baseline)
          assert_unused
          smart -x > "$BASE.baseline.txt" 2>&1
          counters > "$BASE.counters.before"
          poh > "$BASE.poh.before"
          header
          echo
          cat "$BASE.counters.before"
          echo "power_on_hours $(cat "$BASE.poh.before")"
          echo
          echo "saved $BASE.baseline.txt"
          echo "next: sudo disk-burnin longtest $DEV"
          ;;

        longtest)
          assert_unused
          [ -f "$BASE.poh.before" ] || { echo "run baseline first" >&2; exit 1; }
          # A self-test generates no host I/O, so hd-idle parks the drive
          # ~30 min in and the drive aborts the test. Refuse rather than
          # burn 19h producing a log entry the verdict cannot trust.
          if systemctl is-active --quiet hd-idle; then
            cat >&2 <<EOF
      REFUSING: hd-idle is running and will abort this self-test.

      A SMART self-test issues no host I/O, so hd-idle spins the drive down
      after its idle timeout and the drive logs "Aborted by host".

        sudo systemctl stop hd-idle
        sudo disk-burnin longtest $DEV
        # ... and after the verdict:
        sudo systemctl start hd-idle
      EOF
            exit 1
          fi
          smart -t long >/dev/null
          header
          echo "long self-test started. Poll with: sudo disk-burnin verdict $DEV"
          ;;

        burn)
          assert_unused
          [ -f "$BASE.poh.before" ] || { echo "run baseline first" >&2; exit 1; }
          header
          echo
          echo "DESTRUCTIVE: this erases every sector of $DEV."
          echo "Type the serial ($SERIAL) to confirm:"
          read -r confirm
          [ "$confirm" = "$SERIAL" ] || { echo "no match, aborting" >&2; exit 1; }
          # -b 4096 is load-bearing, not cosmetic: badblocks counts in blocks,
          # and at the default 1024 a 10TB drive overflows its 32-bit block
          # counter and aborts with "Value too large for defined data type".
          #
          # One pass, not the default four. The point is to prove the drive
          # survives one full-surface write-read — which is what a SnapRAID
          # parity rebuild does to it — not to scrub it clean.
          badblocks -b 4096 -wsv -t random -o "$BASE.badblocks" "$DEV" 2>&1 \
            | tee "$BASE.burn.log"
          echo "next: sudo disk-burnin verdict $DEV"
          ;;

        verdict)
          [ -f "$BASE.poh.before" ] || { echo "no baseline for $SERIAL" >&2; exit 1; }
          base_poh=$(cat "$BASE.poh.before")
          counters > "$BASE.counters.after"
          smart -x > "$BASE.final.txt" 2>&1

          header
          echo
          echo "--- self-test log (entries at or after baseline hour $base_poh) ---"
          selftest_rows | awk -v since="$base_poh" '$(NF-1)+0 >= since'
          echo
          echo "--- counters: baseline vs now ---"
          if diff -u "$BASE.counters.before" "$BASE.counters.after"; then
            echo "(unchanged)"
          fi
          echo

          bad=0
          [ -s "$BASE.badblocks" ] && bad=$(grep -c . "$BASE.badblocks")
          echo "badblocks bad sectors: $bad"
          echo
          echo "--- verdict ---"
          fail=0

          # Counter movement is the primary signal. Absolute values say little
          # — a drive that shipped with two remapped sectors and holds at two
          # through a full write-read is sound; the same drive going zero to
          # two during the test is failing now.
          if ! diff -q "$BASE.counters.before" "$BASE.counters.after" >/dev/null; then
            echo "FAIL: SMART counters moved during the test (see diff above)"
            fail=1
          fi

          if [ "$bad" -gt 0 ]; then
            echo "FAIL: $bad bad sectors found by badblocks"
            fail=1
          fi

          # Only this test run's entries count: a used drive may carry a
          # failure from a previous owner, and that is the seller's history,
          # not evidence about the drive under our load.
          mine=$(selftest_rows | awk -v since="$base_poh" '$(NF-1)+0 >= since')
          if [ -z "$mine" ]; then
            echo "FAIL: no self-test recorded since baseline — run longtest"
            fail=1
          elif printf '%s\n' "$mine" \
            | grep -qiE 'fail|abort|interrupt|fatal|unknown error|in progress'; then
            # Covers both vocabularies: ATA "Completed: read failure",
            # "Aborted by host"; SCSI "Failed in first segment", "Completed,
            # segment failed". Anything not positively complete fails closed.
            echo "FAIL: self-test did not complete cleanly"
            fail=1
          elif ! printf '%s\n' "$mine" | grep -qi 'completed'; then
            echo "FAIL: no completed self-test found since baseline"
            fail=1
          fi

          if [ "$fail" -eq 0 ]; then
            echo "PASS — safe to put into service"
          else
            echo
            echo "Return it. Reports in $OUTDIR/ are the evidence."
          fi
          exit "$fail"
          ;;

        *)
          usage
          ;;
      esac
    '';
  };
in
{
  environment.systemPackages = [ burnin ];

  systemd.tmpfiles.rules = [ "d /var/lib/disk-burnin 0755 root root -" ];
}

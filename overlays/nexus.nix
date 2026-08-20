(
  self: super:
  let
    optimizedForNexus =
      pkg:
      pkg.overrideAttrs (oldAttrs: {
        env = (oldAttrs.env or { }) // {
          NIX_CFLAGS_COMPILE =
            (oldAttrs.env.NIX_CFLAGS_COMPILE or "")
            + " -O2 -ftree-vectorize -march=sandybridge -mtune=sandybridge";
          NIX_CXXFLAGS_COMPILE =
            (oldAttrs.env.NIX_CFLAGS_COMPILE or "")
            + " -O2 -ftree-vectorize -march=sandybridge -mtune=sandybridge";
        };
      });
  in
  {
    jellyfin = super.jellyfin.override ({
      jellyfin-ffmpeg = optimizedForNexus (
        super.jellyfin-ffmpeg.override ({
          ffmpeg_7-full = super.ffmpeg_7-full.override ({
            withHeadlessDeps = true;
            withNvcodec = true;
          });
        })
      );
    });
    # snapraid 14.9: the direct-I/O test invoked with
    # --test-io-advise-direct fails with EINVAL because O_DIRECT is unsupported
    # on the Nix build sandbox filesystem. This is an environment limitation,
    # not evidence that SnapRAID's direct I/O is broken on the Nexus disks.
    # snapraid 14.7 already had doCheck enabled and passed; this regression
    # arrived with the nixpkgs 14.7 -> 14.9 version bump.
    #
    # optimizedForNexus adds Sandy Bridge CPU flags, changing the derivation so
    # cache.nixos.org cannot substitute it. Whenever the snapraid derivation
    # changes, Nexus must build it from source and cannot have this failure
    # masked by the binary cache.
    #
    # Tracking: https://github.com/NixOS/nixpkgs/issues/505793
    # (OPEN, no fix PR found as of 2026-08-20).
    #
    # doCheck = false disables the full test suite of a parity/data-integrity
    # tool; this is a deliberate trade-off to keep the host buildable. Drop
    # this override once nixos-unstable ships a snapraid whose tests pass in
    # the sandbox: either a release after 14.9 or a nixpkgs-side guard for the
    # direct-I/O test.
    snapraid = optimizedForNexus (super.snapraid.overrideAttrs { doCheck = false; });
    telegram-notify = super.writeShellScriptBin "telegram-notify" ''
      set -euo pipefail

      if [[ -z "''${TELEGRAM_ENV_FILE:-}" ]]; then
        echo "Error: TELEGRAM_ENV_FILE not set" >&2
        exit 1
      fi

      if [[ ! -f "$TELEGRAM_ENV_FILE" ]]; then
        echo "Error: $TELEGRAM_ENV_FILE not found" >&2
        exit 1
      fi

      source "$TELEGRAM_ENV_FILE"

      ${super.curl}/bin/curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        --data chat_id="$CHANNEL_ID" \
        --data parse_mode="Markdown" \
        --data-urlencode "text=$1"
    '';
  }
)

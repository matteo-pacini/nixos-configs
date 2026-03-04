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
    mergerfs = (optimizedForNexus super.mergerfs).overrideAttrs (oldAttrs: {
      env = (oldAttrs.env or { }) // {
        NIX_CFLAGS_COMPILE =
          (oldAttrs.env.NIX_CFLAGS_COMPILE or "")
          + " -Wno-error=stringop-truncation -Wno-error=unused-result";
        NIX_CXXFLAGS_COMPILE =
          (oldAttrs.env.NIX_CFLAGS_COMPILE or "")
          + " -Wno-error=stringop-truncation -Wno-error=unused-result";
      };
    });
    snapraid = optimizedForNexus super.snapraid;
    # Pin psutil to 7.1.2 for Home Assistant due to API changes in psutil 7.2.x
    # that removed named tuples from psutil._common (breaks systemmonitor).
    # Upstream PR: https://github.com/NixOS/nixpkgs/pull/496693
    home-assistant = super.home-assistant.override {
      packageOverrides = _: pySuper: {
        psutil = pySuper.psutil.overridePythonAttrs (oldAttrs: rec {
          version = "7.1.2";
          src = super.fetchFromGitHub {
            inherit (oldAttrs.src) owner repo;
            tag = "release-${version}";
            hash = "sha256-LyGnLrq+SzCQmz8/P5DOugoNEyuH0IC7uIp8UAPwH0U=";
          };
          # psutil 7.1.x has tests at psutil/tests/, not top-level tests/
          enabledTestPaths = [
            "${builtins.placeholder "out"}/${pySuper.python.sitePackages}/psutil/tests/test_system.py"
          ];
          # Don't delete psutil/ dir — tests live inside it in 7.1.x
          preCheck = "";
          nativeCheckInputs = [ pySuper.pytestCheckHook ];
        });
      };
    };
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

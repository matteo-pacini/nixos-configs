{ inputs }:
(
  self: super:
  let
    # Bleeding-edge packages sourced from the nixpkgs-master input instead of
    # the flake's nixos-unstable pin. Imported with the host's own nixpkgs
    # config (carries allowUnfree, needed for claude-code). Bump the lot with
    # `nix flake update nixpkgs-master`.
    masterPkgs = import inputs.nixpkgs-master {
      inherit (super.stdenv.hostPlatform) system;
      config = super.config;
    };
    opencodePkgs = import inputs.nixpkgs-opencode {
      inherit (super.stdenv.hostPlatform) system;
      config = super.config;
    };
  in
  {
    # gh: disable telemetry (https://cli.github.com/telemetry). Nixpkgs does not
    # disable it by default; wrap the binary so every invocation has the env var.
    gh = super.gh.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ super.makeWrapper ];
      postInstall = (old.postInstall or "") + ''
        wrapProgram $out/bin/gh --set GH_TELEMETRY false
      '';
    });

    # Per-host GitHub SSH key rotation (auth + signing). self.callPackage so it
    # picks up the telemetry-wrapped gh above.
    rotate-github-key = self.callPackage ../packages/rotate-github-key.nix { };

    ssh-mesh-renew = self.callPackage ../packages/ssh-mesh-renew.nix { };

    # 2.1.0 follows Apple's 2026 sign-in changes; nixpkgs' 1.6.2 fails to log
    # in. Regenerate packages/xcodes/generated on bump: `swift package resolve`
    # then `swiftpm2nix` in the source checkout.
    xcodes = super.xcodes.overrideAttrs (
      finalAttrs: old: {
        version = "2.1.0";
        src = super.fetchFromGitHub {
          owner = "XcodesOrg";
          repo = "xcodes";
          tag = finalAttrs.version;
          hash = "sha256-BUFcK+r7fDN7KC9PBikRGl355VouZ85ngcmVh7gj6tE=";
        };
        configurePhase = (super.swiftpm2nix.helpers ../packages/xcodes/generated).configure;
      }
    );

    # Posts $1 to the Telegram chat in $TELEGRAM_ENV_FILE (BOT_TOKEN, CHANNEL_ID)
    # using legacy Markdown; callers must escape _ * ` [ in untrusted text.
    # $TELEGRAM_PREFIX, if set, is prepended verbatim.
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
        --data-urlencode "text=''${TELEGRAM_PREFIX:-}$1"
    '';

    # Claude Code: sourced from the nixpkgs-master input (see masterPkgs above)
    # so we track upstream faster than the flake's nixos-unstable pin. Bump with
    # `nix flake update nixpkgs-master`.
    #
    # Wrapper additions on top of upstream (last reviewed against v2.1.123):
    #   - PATH: nodejs is bundled onto claude's wrapped PATH instead of being
    #     installed user-wide. It satisfies the statusLine command
    #     (`npx -y ccstatusline@latest`). This is unrelated to upstream bugs —
    #     pure local-tooling concern.
    #   - PATH (Linux only): wl-clipboard and xclip. Claude shells out to them
    #     for clipboard access; image paste has no fallback without them, and
    #     screenshot-to-clipboard only tries xclip (via Xwayland on Wayland).
    #   - CLAUDE_CODE_AUTO_COMPACT_WINDOW=1000000: partial workaround for the
    #     autocompact threshold collapsing on Opus 4.7 [1m] variants
    #     (https://github.com/anthropics/claude-code/issues/43989, closed as
    #     stale 2026-07-11 without a fix). The
    #     trigger is min(WINDOW_env, detected) × 0.95, and the runtime misreads
    #     `detected` as ~200K for the [1m] variant, so as of v2.1.141+ the
    #     threshold sits at ~190K despite this override — it no longer restores
    #     the full 1M, but dropping it would make the cap worse. Nothing upstream
    #     left to wait on: re-evaluate on claude-code bumps.
    #     WAIT-FOR manual: https://github.com/anthropics/claude-code/issues/43989 (checked 2026-11-03)
    #   - CLAUDE_CODE_CERT_STORE=bundled (Darwin, default only): upstream's
    #     wrapper sets CLAUDE_CODE_CERT_STORE=system (NixOS/nixpkgs#576509), and
    #     on Darwin that store fails OAuth and API calls with
    #     UNABLE_TO_GET_ISSUER_CERT_LOCALLY, even with NODE_EXTRA_CA_CERTS
    #     pointing at the system bundle. Bun's bundled roots are safe from
    #     Bun 1.4.4 (oven-sh/bun#46159): no emSign roots, no Comodo AAA. Before
    #     a claude-code bump, check its embedded Bun is still >= 1.4.4. nixpkgs
    #     has since fixed the Darwin case by exporting NODE_EXTRA_CA_CERTS
    #     (already in the master pin), which is what failed for us above: drop
    #     this only once claude signs in and calls the API on a Mac without it.
    #     WAIT-FOR manual: https://github.com/NixOS/nixpkgs/pull/579756 (checked 2026-11-03)
    #
    # Issues to keep an eye on (no action yet — no clean Nix-level fix today,
    # but watch for upstream changes that would let us address them here):
    #   - #46917: server bills ~20K extra cache-creation tokens per request on
    #     all 2.1.100+ builds. UA-spoof workaround is dead; waiting for a
    #     client-side opt-out flag from Anthropic.
    #     WATCH: https://github.com/anthropics/claude-code/issues/46917
    #   - #28240: `cd` re-prompts on compound bash (`git add && git commit`).
    #     Fixable via a PreToolUse hook in the claude-code module's settings.json
    #     template (not an overlay change) — implement if the friction grows.
    #     WATCH: https://github.com/anthropics/claude-code/issues/28240
    #   - #36168: `--dangerously-skip-permissions` broken since 2.1.78. Only
    #     "fix" is pinning <=v2.1.77, which defeats tracking nixpkgs master.
    #     WATCH: https://github.com/anthropics/claude-code/issues/36168
    claude-code = masterPkgs.claude-code.overrideAttrs (old: {
      postInstall = (old.postInstall or "") + ''
        wrapProgram $out/bin/claude \
          --prefix PATH : ${
            super.lib.makeBinPath (
              [ super.nodejs ]
              ++ super.lib.optionals super.stdenv.hostPlatform.isLinux [
                super.wl-clipboard
                super.xclip
              ]
            )
          } \
          --set CLAUDE_CODE_AUTO_COMPACT_WINDOW 1000000 ${super.lib.optionalString super.stdenv.hostPlatform.isDarwin "\\
          --set-default CLAUDE_CODE_CERT_STORE bundled"}
      '';
    });

    # opencode sourced from the master pin: its OpenAI-chat mapper reports
    # OpenRouter's billed usage.cost (#43818, verified on 2.2.1), whereas
    # nixos-unstable's 2.1.4 still prices OpenRouter turns from the catalog.
    #
    # Temporarily held at 2.2.1 via the nixpkgs-opencode input: on master,
    # 2.2.5's node_modules fails its fixed-output hash on every build (Hydra
    # too, NixOS/nixpkgs#582673). Once the hash fix is merged, switch back to
    # masterPkgs.opencode and drop the nixpkgs-opencode input from flake.nix.
    # WAIT-FOR merged: https://github.com/NixOS/nixpkgs/pull/582675
    opencode = opencodePkgs.opencode;

    # Personal patches, not meant for upstream: load mods from the folders in
    # HERDR_APP_MODS_PATH too (hot reload and icons included). A failing patch
    # after a nixpkgs bump means they need refreshing.
    herdr-desktop = super.herdr-desktop.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        ../patches/herdr-desktop/001-scan-extra-mod-dirs.patch
        ../patches/herdr-desktop/002-hot-reload-extra-mod-dirs.patch
        ../patches/herdr-desktop/003-extra-mod-dir-assets.patch
      ];
    });

    # gnome-shell 50.2: racy SIGSEGV at session start in the vendored gvc
    # subproject — update_card() derefs pa_card_info.active_profile->name, but
    # pipewire-pulse can transiently report a card with zero profiles during
    # bring-up ("profiles inconsistent"), making active_profile NULL. Kills the
    # autologin session on the GNOME hosts (BrightFalls, CauldronLake).
    # Reported upstream as libgvc issue #47, with the fix in MR !38 (open as of
    # 2026-11-03); the patch header predates both. See it for full context.
    # Drop once gnome-shell vendors a gvc with the guard.
    # WAIT-FOR merged: https://gitlab.gnome.org/GNOME/libgnome-volume-control/-/merge_requests/38
    gnome-shell = super.gnome-shell.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        ../patches/gnome-shell/001-gvc-null-active-profile.patch
      ];
      # The parallel g-ir-scanner runs share a writable cache under $HOME; one
      # wipes it on a cache-version mismatch while another is still moving an
      # entry in, failing the build with FileNotFoundError in cachestore.store.
      env = (old.env or { }) // {
        GI_SCANNER_DISABLE_CACHE = "1";
      };
    });
  }
)

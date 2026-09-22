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
    #     (https://github.com/anthropics/claude-code/issues/43989, OPEN). The
    #     trigger is min(WINDOW_env, detected) × 0.95, and the runtime misreads
    #     `detected` as ~200K for the [1m] variant, so as of v2.1.141+ the
    #     threshold sits at ~190K despite this override — it no longer restores
    #     the full 1M, but dropping it would make the cap worse. Re-evaluate
    #     when #43989 closes.
    #
    # Issues to keep an eye on (no action yet — no clean Nix-level fix today,
    # but watch for upstream changes that would let us address them here):
    #   - #46917: server bills ~20K extra cache-creation tokens per request on
    #     all 2.1.100+ builds. UA-spoof workaround is dead; waiting for a
    #     client-side opt-out flag from Anthropic.
    #   - #28240: `cd` re-prompts on compound bash (`git add && git commit`).
    #     Fixable via a PreToolUse hook in the claude-code module's settings.json
    #     template (not an overlay change) — implement if the friction grows.
    #   - #36168: `--dangerously-skip-permissions` broken since 2.1.78. Only
    #     "fix" is pinning <=v2.1.77, which defeats tracking nixpkgs master.
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
          --set CLAUDE_CODE_AUTO_COMPACT_WINDOW 1000000
      '';
    });

    # opencode sourced from the master pin (currently 1.18.18) so it matches the
    # patches below, which apply cleanly across opencode 1.16.2–1.18.18
    # (re-verified with `git apply --check` against 1.18.18 on 2026-08-20).
    # Upstream still hasn't fixed OpenRouter cost reporting (PR #37525 closed
    # unmerged; issues #18440/#454 closed stale, bug still live).
    opencode = masterPkgs.opencode.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        # opencode's getUsage prices a turn as (model rate × tokens) and ignores
        # the authoritative response usage.cost. Prefer
        # providerMetadata.openrouter.usage.cost (usage accounting is force-enabled
        # for the openrouter provider) so per-turn cost reflects OpenRouter's real
        # billing.
        ../modules/home-manager/opencode/patches/openrouter-real-cost.patch
        # Subagent (child-session) cost isn't rolled up into the parent, so no
        # single number shows what a whole run cost. Render a derived whole-tree
        # total in the sidebar next to the session title; per-agent cost stays as
        # is. Client-side only (the TUI already holds every session). See header.
        ../modules/home-manager/opencode/patches/subagent-total-cost.patch
      ];
    });

    # xdg-desktop-portal-1.20.4: two integration tests fail in the Nix build
    # sandbox because the validator helpers (xdg-desktop-portal-validate-sound
    # and -validate-icon) shell out to bwrap, which tries to create a nested
    # user namespace and trips on:
    #     bwrap: Can't mount proc on /newroot/proc: Operation not permitted
    # The failures:
    #   - integration/dynamiclauncher (exit status 1)
    #   - integration/notification    (pytest test_sound_fd: "invalid sound:
    #                                  The sound data is invalid (36)" because
    #                                  the validator subprocess died)
    # Environment-driven, not a real package bug. Affects the gaming Linux
    # hosts (CauldronLake / BrightFalls) that pull xdg-desktop-portal in via
    # their desktop closure.
    #
    # Skipping the check phase until upstream ships a fix. Status as of
    # 2026-07-28: nixos-unstable still packages 1.20.4 with no relevant
    # change; the package's XDP_TEST_IN_CI escape hatch does not cover these
    # two tests; upstream 1.21.x/1.22.x release notes mention nothing about
    # the bwrap/nested-userns failures. The closest tracking issue is open
    # with no activity and was filed for a different trigger (a custom
    # enableGeoLocation override), but the failing test is the same one:
    #   Issue: https://github.com/NixOS/nixpkgs/issues/511228 (OPEN)
    # Drop this override once nixos-unstable ships an xdg-desktop-portal whose
    # checkPhase passes inside the build sandbox.
    xdg-desktop-portal = super.xdg-desktop-portal.overrideAttrs (_: {
      doCheck = false;
    });

    # gnome-shell 50.2: racy SIGSEGV at session start in the vendored gvc
    # subproject — update_card() derefs pa_card_info.active_profile->name, but
    # pipewire-pulse can transiently report a card with zero profiles during
    # bring-up ("profiles inconsistent"), making active_profile NULL. Kills the
    # autologin session on the GNOME hosts (BrightFalls, CauldronLake).
    # Unfixed on libgvc master and pipewire 1.6.7 as of 2026-07-09; see the
    # patch header for full context. Drop once the vendored gvc gains the guard.
    gnome-shell = super.gnome-shell.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        ../patches/gnome-shell/001-gvc-null-active-profile.patch
      ];
    });
  }
)

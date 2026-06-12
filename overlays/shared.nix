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

    # Claude Code: sourced from the nixpkgs-master input (see masterPkgs above)
    # so we track upstream faster than the flake's nixos-unstable pin. Bump with
    # `nix flake update nixpkgs-master`.
    #
    # Wrapper additions on top of upstream (last reviewed against v2.1.123):
    #   - PATH: nodejs, rtk, and jq are bundled onto claude's wrapped PATH
    #     instead of being installed user-wide.
    #       * nodejs: so RTK's claude-code hook (and any other node-based hook
    #         under ~/.claude/hooks) can find `node`. Also satisfies the
    #         statusLine command (`npx -y ccstatusline@latest`).
    #       * rtk: needed by ~/.claude/hooks/rtk-rewrite.sh, which rewrites bash
    #         commands inside Claude sessions. Subprocesses spawned by claude
    #         inherit this PATH, so `rtk <cmd>` invocations from inside a session
    #         resolve. NOT on the user's interactive shell PATH by design.
    #       * jq: needed by the rtk-rewrite hook to parse/emit JSON. macOS has
    #         /usr/bin/jq but NixOS hosts don't install it by default.
    #     This is unrelated to upstream bugs — pure local-tooling concern.
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
          --prefix PATH : ${super.nodejs}/bin:${self.rtk}/bin:${super.jq}/bin \
          --set CLAUDE_CODE_AUTO_COMPACT_WINDOW 1000000
      '';
    });

    # rtk: sourced from the nixpkgs-master input (see masterPkgs above) so we
    # track upstream faster than the flake's nixos-unstable pin. The rtk binary
    # embeds an expected hash for the bundled rtk-rewrite.sh hook; when upstream
    # pushes a hook content change ahead of a binary release, anyone on a
    # nixpkgs lag sees the integrity check fail. The master pin lets us bump rtk
    # as soon as upstream tags a release that bundles the new hook. After a bump
    # re-sync the vendored hook with
    # `modules/home-manager/claude-code/update-rtk.sh`.
    rtk = masterPkgs.rtk;

    # openldap-2.6.13: the syncreplication tests are timing-sensitive and fail
    # on slow / sandboxed builders ("provider and consumer databases differ").
    # First test017 fell over, then surgically skipping it just exposed the
    # next one (test019-syncreplication-cascade). The failure cascades into
    # bottles / lutris / wine FHS envs pulled in by the gaming hosts
    # (BrightFalls, CauldronLake), killing their full system builds in CI.
    #
    # Disabling the check phase entirely until upstream lands a real fix —
    # going test-by-test is whack-a-mole.
    #   Issue: https://github.com/NixOS/nixpkgs/issues/516392 (CLOSED, links to PR)
    #   Fix:   https://github.com/NixOS/nixpkgs/pull/516445   (OPEN as of 2026-05-05,
    #          only patches test017 — won't fully unbreak us; revisit when
    #          upstream addresses test019 too)
    # Drop this override once nixos-unstable ships a build that passes checks.
    openldap = super.openldap.overrideAttrs (_: {
      doCheck = false;
    });

    # fwupd-2.1.1: two test cases fail in the Nix build sandbox because they
    # expect a running desktop session:
    #   - fu-engine-gtypes-test: FuPluginLogind aborts with
    #     "GDBus.Error:org.freedesktop.DBus.Error.AccessDenied: Permission
    #     denied" when it tries to call logind.Inhibit (no logind in sandbox).
    #   - fwupd-client-test:     killed by SIGABRT (related fallout).
    # Affects the gaming hosts (CauldronLake / BrightFalls) that pull fwupd
    # in transitively, killing the system build in CI.
    #
    # Skipping the check phase until upstream nixpkgs gets a fix. There's no
    # tracking issue specific to this; the next-version bump PR doesn't
    # address tests either, so don't expect it to land a fix on its own.
    #   2.1.2 bump:    https://github.com/NixOS/nixpkgs/pull/513368 (OPEN, x86_64-linux only)
    # Drop this once nixos-unstable ships a fwupd whose checkPhase passes.
    fwupd = super.fwupd.overrideAttrs (_: {
      doCheck = false;
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
    # Same family as openldap/fwupd above — environment-driven, not a real
    # package bug. Affects the gaming Linux hosts (CauldronLake / BrightFalls)
    # that pull xdg-desktop-portal in via their desktop closure.
    #
    # Skipping the check phase until upstream nixpkgs ships a fix. The closest
    # tracking issue is open with no comments and was filed for a different
    # trigger (a custom enableGeoLocation override), but the failing test is
    # the same one:
    #   Issue: https://github.com/NixOS/nixpkgs/issues/511228 (OPEN)
    # Drop this override once nixos-unstable ships an xdg-desktop-portal whose
    # checkPhase passes inside the build sandbox.
    xdg-desktop-portal = super.xdg-desktop-portal.overrideAttrs (_: {
      doCheck = false;
    });

    # jellyfin-tui: cover art flickers on every redraw when launched inside a
    # zellij pane because zellij's Kitty/Sixel passthrough is unreliable
    # (zellij-org/zellij#2814, #2576). The patch forces Picker::halfblocks() when
    # the ZELLIJ env var is set, so the art renders as ordinary colored cells
    # instead of out-of-band graphics escapes. See the patch header for full
    # context. Drop this once zellij implements the Kitty graphics protocol.
    jellyfin-tui = super.jellyfin-tui.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        ../patches/jellyfin-tui/001-zellij-halfblocks.patch
      ];
    });
  }
)

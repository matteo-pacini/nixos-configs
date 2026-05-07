(self: super: {
  # gh: disable telemetry (https://cli.github.com/telemetry). Nixpkgs does not
  # disable it by default; wrap the binary so every invocation has the env var.
  gh = super.gh.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ super.makeWrapper ];
    postInstall = (old.postInstall or "") + ''
      wrapProgram $out/bin/gh --set GH_TELEMETRY false
    '';
  });

  # Claude Code: vendored from nixpkgs master into ../packages/claude-code/ so
  # we can track upstream faster than the flake's nixos-unstable pin. Refresh
  # with `./packages/claude-code/update.sh`.
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
  #   - CLAUDE_CODE_AUTO_COMPACT_WINDOW=1000000: works around the autocompact
  #     400k cap on Opus 4.7 [1m] variants
  #     (https://github.com/anthropics/claude-code/issues/43989, OPEN). v2.1.117
  #     fixed the 200K→1M path but explicitly not this case; v2.1.118–123 ship
  #     no autocompact-threshold fixes. Re-evaluate when #43989 closes.
  #   - ENABLE_PROMPT_CACHING_1H=1: forces 1h prompt caching even though the
  #     original bug (#45381) closed in v2.1.108. Client-side default is still
  #     5m for subagents and most query types — see follow-up
  #     https://github.com/anthropics/claude-code/issues/54006 (OPEN). Anthropic
  #     has stated they'll flip the default + ship dedicated env vars; drop
  #     this when that lands.
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
  claude-code = (super.callPackage ../packages/claude-code/package.nix { }).overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      wrapProgram $out/bin/claude \
        --prefix PATH : ${super.nodejs}/bin:${self.rtk}/bin:${super.jq}/bin \
        --set CLAUDE_CODE_AUTO_COMPACT_WINDOW 1000000 \
        --set ENABLE_PROMPT_CACHING_1H 1
    '';
  });

  # rtk: vendored from nixpkgs master into ../packages/rtk/ so we can track
  # upstream faster than the flake's nixos-unstable pin. The rtk binary embeds
  # an expected hash for the bundled rtk-rewrite.sh hook; when upstream pushes
  # a hook content change ahead of a binary release, anyone on a nixpkgs lag
  # sees the integrity check fail. Vendoring lets us bump the rtk derivation
  # as soon as upstream tags a release that bundles the new hook.
  # Refresh with `./packages/rtk/update.sh`.
  rtk = super.callPackage ../packages/rtk/package.nix { };

  # opencode: vendored from nixpkgs master into ../packages/opencode/ so we
  # can track upstream faster than the flake's nixos-unstable pin. Upstream
  # ships frequent releases that fix provider/transform bugs and adjust
  # agent behavior we depend on (see modules/home-manager/opencode.nix for
  # the live list of issues we're chasing); waiting for nixos-unstable to
  # pick them up noticeably lags day-to-day usage.
  # Refresh with `./packages/opencode/update.sh`.
  opencode = super.callPackage ../packages/opencode/package.nix { };

  # Token usage tracker for AI coding agents
  tokscale = super.callPackage ../packages/tokscale.nix { };

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
})

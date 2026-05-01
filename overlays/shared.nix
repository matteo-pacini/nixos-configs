(self: super: {
  # gh: disable telemetry (https://cli.github.com/telemetry). Nixpkgs does not
  # disable it by default; wrap the binary so every invocation has the env var.
  gh = super.gh.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ super.makeWrapper ];
    postInstall = (old.postInstall or "") + ''
      wrapProgram $out/bin/gh --set GH_TELEMETRY false
    '';
  });

  # Token usage tracker for AI coding agents
  # TODO: Remove local package + overlay once merged upstream.
  #   tokscale: init at 2.0.26 (PR aims to add to nixpkgs)
  #   https://github.com/NixOS/nixpkgs/pull/510494
  tokscale = super.callPackage ../packages/tokscale.nix { };

  # Workaround: openldap 2.6.13 test017-syncreplication-refresh is flaky in the
  # Nix sandbox and fails on x86_64-linux, breaking anything depending on wine
  # (e.g. bottles, lutris).
  # Affected hosts in this flake: CauldronLake, BrightFalls (x86_64)
  # Upstream issues:
  #   - openldap: test checks won't let it compile on x86_64
  #     https://github.com/NixOS/nixpkgs/issues/514113
  #   - Build failure: lutris-free
  #     https://github.com/NixOS/nixpkgs/issues/513245
  # TODO: Remove once upstream disables the flaky test or releases a fix.
  openldap = super.openldap.overrideAttrs (old: {
    doCheck = false;
  });

  # Workaround: fwupd 2.1.1 tests call Inhibit on systemd-logind via D-Bus,
  # which fails in the Nix sandbox with AccessDenied. Affects CauldronLake.
  # Keep an eye on upstream for a proper fix:
  #   - fwupd: 2.1.1 -> 2.1.2 (may or may not resolve test failures)
  #     https://github.com/NixOS/nixpkgs/pull/513368
  #   - Also watch for new issues/PRs specifically about fwupd logind/D-Bus
  #     test failures in sandboxed builds.
  # TODO: Remove once upstream fixes the sandboxed test failures.
  fwupd = super.fwupd.overrideAttrs (old: {
    doCheck = false;
  });

  # Workaround: xdg-desktop-portal 1.20.4 integration tests
  # (integration/dynamiclauncher and integration/notification) fail in the
  # Nix sandbox / CI environment. Affects CauldronLake.
  # No exact upstream tracker yet for these two tests. Loosely related
  # (same package, sandbox test flakiness — different root cause):
  #   - xdg-desktop-portal: test failed (integration/location, geoclue disabled)
  #     https://github.com/NixOS/nixpkgs/issues/511228
  # TODO: Remove once upstream fixes the sandboxed test failures.
  xdg-desktop-portal = super.xdg-desktop-portal.overrideAttrs (old: {
    doCheck = false;
  });

  # Workaround: rusty-v8 147.2.1 `tests/slots.rs` aborts under Nixpkgs'
  # libc++ hardening with "vector[] index out of bounds", breaking Deno and
  # nvf builds.
  # Upstream issue:
  #   - Build failure: deno
  #     https://github.com/NixOS/nixpkgs/issues/511900
  # TODO: Remove once upstream fixes the slots test or updates rusty-v8/deno.
  deno = super.deno.override {
    librusty_v8 = super.deno.librusty_v8.overrideAttrs (old: {
      checkFlags = old.checkFlags ++ [ "--skip=slots" ];
    });
  };
})

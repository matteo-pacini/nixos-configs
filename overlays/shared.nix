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
})

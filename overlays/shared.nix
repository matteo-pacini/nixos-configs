(self: super: {
  # Claude Code wrapper: env vars to tune behaviour under Nix.
  # Appends to upstream postInstall (which sets DISABLE_AUTOUPDATER,
  # FORCE_AUTOUPDATE_PLUGINS, DISABLE_INSTALLATION_CHECKS, unsets DEV,
  # and adds procps/bubblewrap/socat to PATH).
  #
  # Relevant issues & references:
  #   - Effort level ignored (>=113):   https://github.com/anthropics/claude-code/issues/50099
  #   - Autocompact window regression:  https://github.com/anthropics/claude-code/issues/43989
  #   - 1h cache TTL vs telemetry:      https://github.com/anthropics/claude-code/issues/45381
  claude-code = super.claude-code.overrideAttrs (old: {
    postInstall = old.postInstall + ''
      wrapProgram $out/bin/claude \
        --set CLAUDE_CODE_EFFORT_LEVEL max \
        --set CLAUDE_CODE_AUTO_COMPACT_WINDOW 400000 \
        --set ENABLE_PROMPT_CACHING_1H 1
    '';
  });

  # gh: disable telemetry (https://cli.github.com/telemetry). Nixpkgs does not
  # disable it by default; wrap the binary so every invocation has the env var.
  gh = super.gh.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ super.makeWrapper ];
    postInstall = (old.postInstall or "") + ''
      wrapProgram $out/bin/gh --set GH_TELEMETRY false
    '';
  });
})

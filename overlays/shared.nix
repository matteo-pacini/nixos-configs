(self: super: {
  # Claude Code wrapper: env vars to tune behaviour under Nix.
  # Appends to upstream postInstall (which sets DISABLE_AUTOUPDATER,
  # FORCE_AUTOUPDATE_PLUGINS, DISABLE_INSTALLATION_CHECKS, unsets DEV,
  # and adds procps/bubblewrap/socat to PATH).
  #
  # Relevant issues & references:
  #   - Quality / thinking regression:  https://github.com/anthropics/claude-code/issues/42796
  #   - Autocompact window regression:  https://github.com/anthropics/claude-code/issues/43989
  #   - Effort level ignored (>=113):   https://github.com/anthropics/claude-code/issues/50099
  #   - Reddit investigation:           https://www.reddit.com/r/ClaudeCode/comments/1sj10ou/
  claude-code = super.claude-code.overrideAttrs (old: {
    postInstall = old.postInstall + ''
      wrapProgram $out/bin/claude \
        --set CLAUDE_CODE_EFFORT_LEVEL max \
        --set CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING 1 \
        --set MAX_THINKING_TOKENS 63999 \
        --set CLAUDE_CODE_AUTO_COMPACT_WINDOW 400000
    '';
  });
})

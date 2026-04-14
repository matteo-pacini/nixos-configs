(self: super: {
  # https://github.com/anthropics/claude-code/issues/46917
  # https://github.com/anthropics/claude-code/issues/42796
  claude-code = super.claude-code.overrideAttrs (old: {
    postInstall = ''
      wrapProgram $out/bin/claude \
        --set DISABLE_AUTOUPDATER 1 \
        --unset DEV \
        --set ANTHROPIC_CUSTOM_HEADERS "User-Agent: claude-cli/2.1.98 (external, sdk-cli)" \
        --set CLAUDE_CODE_ALWAYS_ENABLE_EFFORT 1 \
        --set CLAUDE_CODE_EFFORT_LEVEL max \
        --set CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING 1 \
        --set MAX_THINKING_TOKENS 63999 \
        --set CLAUDE_CODE_AUTO_COMPACT_WINDOW 400000
    '';
  });
})

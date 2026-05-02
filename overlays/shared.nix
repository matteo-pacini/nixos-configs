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
  #   - PATH: nodejs and rtk are bundled onto claude's wrapped PATH instead of
  #     being installed user-wide.
  #       * nodejs: so RTK's claude-code hook (and any other node-based hook
  #         under ~/.claude/hooks) can find `node`. Also satisfies the
  #         statusLine command (`npx -y ccstatusline@latest`).
  #       * rtk: needed by ~/.claude/hooks/rtk-rewrite.sh, which rewrites bash
  #         commands inside Claude sessions. Subprocesses spawned by claude
  #         inherit this PATH, so `rtk <cmd>` invocations from inside a session
  #         resolve. NOT on the user's interactive shell PATH by design.
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
        --prefix PATH : ${super.nodejs}/bin:${super.rtk}/bin \
        --set CLAUDE_CODE_AUTO_COMPACT_WINDOW 1000000 \
        --set ENABLE_PROMPT_CACHING_1H 1
    '';
  });

  # Token usage tracker for AI coding agents
  tokscale = super.callPackage ../packages/tokscale.nix { };
})

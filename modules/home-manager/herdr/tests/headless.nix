# What a host with herdr-core and no desktop app gets: every label producer
# its agents need, so an app on another machine can draw them, and none of the
# workbench's mods. `home` is such a host's Home Manager configuration.
#   nix build .#checks.x86_64-linux.herdr-headless
{ pkgs, home }:
let
  inherit (pkgs) lib;
  settings = home.custom.claude-code.extraSettings;
  packageNames = map (p: p.name or "") home.home.packages;
  hookEvents = lib.attrNames (settings.hooks or { });

  cases = {
    "the host has no workbench" = !home.custom.herdr.workbench.enable;
    "statusLine is claude-statusline" = lib.hasSuffix "/bin/claude-statusline" (
      settings.statusLine.command or ""
    );
    "Claude hooks on every event" = lib.all (e: lib.elem e hookEvents) [
      "PermissionRequest"
      "PostToolUse"
      "Stop"
      "UserPromptSubmit"
      "SessionStart"
      "SessionEnd"
    ];
    "SessionStart has the session and title hooks" =
      lib.length (settings.hooks.SessionStart or [ ]) == 2;
    "Claude Code loads the keep-warm mod" = (settings.env.CLAUDE_CODE_PLUGIN_DIRS or null) != null;
    "the keep-warm mod is installed" = home.home.activation ? herdrKeepWarmMod;
    "the Codex hooks are merged" = home.home.activation ? herdrCodexHooks;
    "no workbench mods" = !(home.home.activation ? herdrWorkbenchMods);
    "herdr-agent-ask is installed" = lib.elem "herdr-agent-ask" packageNames;
    "herdr-codex-labels is installed" = lib.elem "herdr-codex-labels" packageNames;
    "the opencode plugin is installed" = home.xdg.configFile ? "opencode/plugins/herdr-labels.js";
  };
  failures = lib.attrNames (lib.filterAttrs (_: ok: !ok) cases);
in
{
  herdr-headless =
    pkgs.runCommand "herdr-headless-tests"
      {
        failures = builtins.toJSON failures;
        passAsFile = [ "failures" ];
      }
      ''
        if [ "$(cat "$failuresPath")" != "[]" ]; then
          echo "headless host is missing:"
          ${lib.getExe pkgs.jq} . "$failuresPath"
          exit 1
        fi
        touch $out
      '';
}

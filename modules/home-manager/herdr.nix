{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.herdr;

  # Sets the context and cache labels the agent-tree mod draws, then renders
  # ccstatusline as the plain statusLine does.
  claudeStatusLine = pkgs.writeShellApplication {
    name = "claude-statusline";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.jq
      pkgs.herdr-core
    ];
    text = builtins.readFile ./herdr/claude-statusline.sh;
  };
in
{
  options.custom.herdr = {
    enable = lib.mkEnableOption "herdr-core (`hc`), the server that runs Herdr's terminals and agents";
    desktop = lib.mkEnableOption "the Herdr desktop app";
    mods.agentTree.enable = lib.mkEnableOption ''
      the desktop app's `agent-tree` layout: the Agents sidebar as host > space > tab > agent,
      each agent named by its `agent.name` terminal label, with Claude's context fill and
      prompt-cache time left. Pick it once per machine with
      `herdr-app do layout.switch --name agent-tree`
    '';
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        home.packages = [ pkgs.herdr-core ] ++ lib.optional cfg.desktop pkgs.herdr-desktop;

        # Offered in the desktop app's theme picker. Only the theme file is managed:
        # the picked theme lives in herdr-app's own writable layout state.
        xdg.configFile."herdr-app/themes/dracula.json" = lib.mkIf cfg.desktop {
          source = ./herdr/dracula.json;
        };
      }

      (lib.mkIf cfg.mods.agentTree.enable {
        assertions = [
          {
            assertion = cfg.desktop;
            message = "custom.herdr.mods.agentTree needs custom.herdr.desktop.";
          }
        ];

        # Copied, not linked: herdr-app (0.1.10) reports "no `main.js`" when a mod's
        # main.js is a symlink. Replaces whatever is there, hand-made copies included.
        home.activation.herdrAgentTreeMod = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          dir="${config.xdg.configHome}/herdr-app/mods/agent-tree"
          run rm -f "$dir/main.js" "$dir/mod.json"
          run install -Dm644 ${./herdr/agent-tree/main.js} "$dir/main.js"
          run install -Dm644 ${./herdr/agent-tree/mod.json} "$dir/mod.json"
        '';

        # A snapshot of herdr-app's shipped `main` layout with the agents block
        # swapped; shipped layouts live in the binary, so re-snapshot it when
        # upstream changes `main`. force: replaces hand-made copies instead of
        # failing activation.
        xdg.configFile."herdr-app/layouts/agent-tree.json" = {
          source = ./herdr/layouts/agent-tree.json;
          force = true;
        };

        custom.claude-code.extraSettings.statusLine = {
          type = "command";
          command = lib.getExe claudeStatusLine;
          padding = 0;
          refreshInterval = 10;
        };
      })
    ]
  );
}

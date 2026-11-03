{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.herdr;

  # Claude panes come back from a reboot as plain shells; these two put
  # `claude --resume <id>` back in them. See the scripts' headers.
  claudeSession = pkgs.writeShellApplication {
    name = "herdr-claude-session";
    runtimeInputs = [
      pkgs.herdr-core
      pkgs.jq
    ];
    text = builtins.readFile ./herdr/claude-session.sh;
  };
  claudeResume = pkgs.writeShellApplication {
    name = "herdr-claude-resume";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.herdr-core
      pkgs.jq
    ];
    text = builtins.readFile ./herdr/claude-resume.sh;
  };

  # Sets the context and cache labels the agent-tree mod draws, then renders
  # ccstatusline as the plain statusLine does.
  claudeStatusLine = pkgs.writeShellApplication {
    name = "claude-statusline";
    runtimeInputs = [
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
      prompt-cache time left. The first activation with the app open shows it
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

        # Declared here because the claude-code module rewrites settings.json on
        # every activation, dropping hooks added any other way.
        custom.claude-code.extraSettings = lib.mkIf config.custom.claude-code.enable {
          hooks = {
            SessionStart = [
              {
                hooks = [
                  {
                    type = "command";
                    command = "${lib.getExe claudeSession} start";
                  }
                ];
              }
            ];
            SessionEnd = [
              {
                hooks = [
                  {
                    type = "command";
                    command = "${lib.getExe claudeSession} end";
                  }
                ];
              }
            ];
          };
        };

        systemd.user.services.herdr-claude-resume = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
          Unit.Description = "Resume Claude sessions in recovered herdr-core terminals";
          Service = {
            ExecStart = lib.getExe claudeResume;
            Restart = "always";
            RestartSec = 5;
          };
          Install.WantedBy = [ "default.target" ];
        };

        launchd.agents.herdr-claude-resume = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
          enable = true;
          config = {
            ProgramArguments = [ (lib.getExe claudeResume) ];
            RunAtLoad = true;
            KeepAlive = true;
            StandardOutPath = "${config.home.homeDirectory}/Library/Logs/herdr-claude-resume.log";
            StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/herdr-claude-resume.log";
          };
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

        # Shows the layout once per machine, so a later pick of another layout
        # sticks. The shown layout is the app's own state, so this goes through
        # the running window; with no window open it retries on the next activation.
        home.activation.herdrAgentTreeLayout =
          let
            herdrApp = lib.getExe' pkgs.herdr-desktop "herdr-app";
          in
          lib.hm.dag.entryAfter [ "linkGeneration" ] ''
            marker="${config.xdg.stateHome}/herdr-app/agent-tree-shown"
            if [ ! -e "$marker" ] && ${herdrApp} status >/dev/null 2>&1; then
              if run ${herdrApp} do layout.switch --name agent-tree >/dev/null; then
                run mkdir -p "$(dirname "$marker")"
                run touch "$marker"
              fi
            fi
          '';

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

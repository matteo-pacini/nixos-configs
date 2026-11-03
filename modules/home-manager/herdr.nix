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

  # Sets the context, cache, model and effort labels the agent-tree mod draws, then renders
  # ccstatusline as the plain statusLine does.
  claudeStatusLine = pkgs.writeShellApplication {
    name = "claude-statusline";
    runtimeInputs = [
      pkgs.jq
      pkgs.herdr-core
    ];
    text = builtins.readFile ./herdr/claude-statusline.sh;
  };

  # The agent-tree layout, plus the deploy block beside the work area when
  # mods.deploy is on. Generated rather than a second snapshot of `main`.
  agentTreeLayout =
    let
      deployBlock = {
        id = "deploy";
        type = "block";
        content.mod = "deploy";
        size.px = 340;
        min = 280;
        max = 600;
      };
      addDeploy =
        node:
        if node.id or null == "work-body" then
          node // { children = node.children ++ [ deployBlock ]; }
        else if node ? children then
          node // { children = map addDeploy node.children; }
        else
          node;
    in
    if cfg.mods.deploy.enable then
      pkgs.writeText "agent-tree.json" (
        builtins.toJSON (addDeploy (lib.importJSON ./herdr/layouts/agent-tree.json))
      )
    else
      ./herdr/layouts/agent-tree.json;
in
{
  options.custom.herdr = {
    enable = lib.mkEnableOption "herdr-core (`hc`), the server that runs Herdr's terminals and agents";
    desktop = lib.mkEnableOption "the Herdr desktop app";
    mods.agentTree.enable = lib.mkEnableOption ''
      the desktop app's `agent-tree` layout: the Agents sidebar as host > space > tab > agent,
      each agent named by its `agent.name` terminal label, with Claude's model, effort,
      context fill and prompt-cache time left. The first activation with the app open shows it
    '';
    mods.deploy.enable = lib.mkEnableOption ''
      the nixos-configs panel in the agent-tree layout: the deploy pipeline
      (master, build.yml, the deploy branch, each host's comin) above the
      repo's WAIT-FOR / WATCH tags and their upstream status. Shown only while
      the focused terminal is in a checkout of this repo. Needs `gh` signed in
      and SSH to the other hosts
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
        # main.js is a symlink. The folder is replaced whole, hand-made copies and
        # stale files included; the app regenerates its own typings in it on start.
        home.activation.herdrAgentTreeMod = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          dir="${config.xdg.configHome}/herdr-app/mods/agent-tree"
          run rm -rf "$dir"
          run install -Dm644 ${./herdr/agent-tree/main.js} "$dir/main.js"
          run install -Dm644 ${./herdr/agent-tree/mod.json} "$dir/mod.json"
        '';

        # A snapshot of herdr-app's shipped `main` layout with the agents block
        # swapped; shipped layouts live in the binary, so re-snapshot it when
        # upstream changes `main`. force: replaces hand-made copies instead of
        # failing activation.
        xdg.configFile."herdr-app/layouts/agent-tree.json" = {
          source = agentTreeLayout;
          force = true;
        };

        # Shows the layout once per machine, so a later pick of another layout
        # sticks. A running window switches at once. With none open (activation
        # at boot), the app's shared.json, where it keeps the shown layout, is set
        # so the next start opens on it.
        home.activation.herdrAgentTreeLayout =
          let
            herdrApp = lib.getExe' pkgs.herdr-desktop "herdr-app";
          in
          lib.hm.dag.entryAfter [ "linkGeneration" ] ''
            marker="${config.xdg.stateHome}/herdr-app/agent-tree-shown"
            shared="${config.xdg.configHome}/herdr-app/shared.json"
            if [ ! -e "$marker" ]; then
              shown=0
              if ${herdrApp} status >/dev/null 2>&1; then
                run ${herdrApp} do layout.switch --name agent-tree >/dev/null && shown=1
              else
                tmp=$(mktemp)
                { cat "$shared" 2>/dev/null || echo '{}'; } |
                  ${lib.getExe pkgs.jq} '.layout = "agent-tree"' >"$tmp" &&
                  run install -Dm644 "$tmp" "$shared" && shown=1
                rm -f "$tmp"
              fi
              if [ "$shown" = 1 ]; then
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

      (lib.mkIf cfg.mods.deploy.enable {
        assertions = [
          {
            assertion = cfg.mods.agentTree.enable;
            message = "custom.herdr.mods.deploy lives in the agent-tree layout; enable custom.herdr.mods.agentTree.";
          }
        ];

        # Copied and replaced whole, like agent-tree above.
        home.activation.herdrDeployMod = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          dir="${config.xdg.configHome}/herdr-app/mods/deploy"
          run rm -rf "$dir"
          run install -Dm644 ${./herdr/deploy/main.js} "$dir/main.js"
          run install -Dm644 ${./herdr/deploy/watch.js} "$dir/watch.js"
          run install -Dm644 ${./herdr/deploy/mod.json} "$dir/mod.json"
        '';
      })
    ]
  );
}

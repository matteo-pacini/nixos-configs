# herdr-core and the desktop app, Claude sessions that survive a reboot, and
# the service behind the workbench's keep-cache-warm switch.
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
    text = builtins.readFile ./scripts/claude-session.sh;
  };
  claudeResume = pkgs.writeShellApplication {
    name = "herdr-claude-resume";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.herdr-core
      pkgs.jq
    ];
    text = builtins.readFile ./scripts/claude-resume.sh;
  };

  # Refreshes the prompt cache of the Claude panes switched to keep warm in
  # the pane-header mod. See the script's header.
  claudeKeepWarm = pkgs.writeShellApplication {
    name = "herdr-claude-keep-warm";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.gnugrep
      pkgs.gnused
      pkgs.herdr-core
      pkgs.jq
    ];
    text = builtins.readFile ./scripts/claude-keep-warm.sh;
  };
  # The switch and the labels the service reads come with the workbench.
  keepWarm = cfg.workbench.enable && config.custom.claude-code.enable;

  # herdr-agent-ask is installed by agent-labels.nix. Called by its path in the
  # profile, so an older copy elsewhere on PATH can't shadow it.
  agentAskHook = [
    {
      hooks = [
        {
          type = "command";
          command = "${config.home.profileDirectory}/bin/herdr-agent-ask";
        }
      ];
    }
  ];
in
{
  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.herdr-core ] ++ lib.optional cfg.desktop pkgs.herdr-desktop;

    # Offered in the desktop app's theme picker. Only the theme file is managed:
    # the picked theme lives in herdr-app's own writable layout state.
    xdg.configFile."herdr-app/themes/dracula.json" = lib.mkIf cfg.desktop {
      source = ./themes/dracula.json;
    };

    # Declared here because the claude-code module rewrites settings.json on
    # every activation, dropping hooks added any other way. Every herdr hook is
    # in this one definition: extraSettings is `types.attrs`, which merges
    # definitions shallowly, so a second `hooks` elsewhere would replace this one.
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
      }
      # agent.ask: set when a prompt shows, cleared by the
      # rest. A denied prompt fires none of them.
      // lib.optionalAttrs cfg.workbench.enable {
        PermissionRequest = agentAskHook;
        PostToolUse = agentAskHook;
        UserPromptSubmit = agentAskHook;
        Stop = agentAskHook;
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

    systemd.user.services.herdr-claude-keep-warm =
      lib.mkIf (keepWarm && pkgs.stdenv.hostPlatform.isLinux)
        {
          Unit.Description = "Keep the prompt cache of chosen Claude panes in herdr-core warm";
          Service = {
            ExecStart = lib.getExe claudeKeepWarm;
            Restart = "always";
            RestartSec = 5;
          };
          Install.WantedBy = [ "default.target" ];
        };

    launchd.agents.herdr-claude-keep-warm = lib.mkIf (keepWarm && pkgs.stdenv.hostPlatform.isDarwin) {
      enable = true;
      config = {
        ProgramArguments = [ (lib.getExe claudeKeepWarm) ];
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/herdr-claude-keep-warm.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/herdr-claude-keep-warm.log";
      };
    };
  };
}

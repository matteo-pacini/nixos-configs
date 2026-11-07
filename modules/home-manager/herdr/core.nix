# herdr-core and the desktop app, and Claude sessions that survive a reboot.
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

  # herdr-agent-ask is installed by agent-labels.nix; hooks call it by name.
  agentAskHook = [
    {
      hooks = [
        {
          type = "command";
          command = "herdr-agent-ask";
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
  };
}

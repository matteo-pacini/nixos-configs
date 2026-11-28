# herdr-core and the desktop app, Claude sessions that survive a reboot, the
# Claude Code mod behind the workbench's keep-cache-warm switch, and the hook
# that gives a Claude session the name its terminal was renamed to.
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

  # Where the keep-warm mod is installed, as Claude Code is told of it: its
  # CLAUDE_CODE_PLUGIN_DIRS takes `~`. A copy, not a store path: Claude Code
  # writes the mod's type definitions into its folder.
  keepWarmMod = "~/.claude/herdr-mods/keep-warm";

  # Gives a Claude session the name its terminal was renamed to in the
  # workbench. See the script's header.
  claudeTitle = pkgs.writeShellApplication {
    name = "herdr-claude-title";
    runtimeInputs = [
      pkgs.herdr-core
      pkgs.jq
    ];
    text = builtins.readFile ./scripts/claude-title.sh;
  };
  claudeTitleHook = [
    {
      hooks = [
        {
          type = "command";
          command = lib.getExe claudeTitle;
        }
      ];
    }
  ];

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
        ]
        ++ claudeTitleHook;
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
        # agent.ask: set when a prompt shows, cleared by the
        # rest. A denied prompt fires none of them.
        PermissionRequest = agentAskHook;
        PostToolUse = agentAskHook;
        UserPromptSubmit = agentAskHook ++ claudeTitleHook;
        Stop = agentAskHook;
      };
      # Every Claude Code session loads the mod; it pings only in a terminal
      # whose switch is on. See its header.
      env.CLAUDE_CODE_PLUGIN_DIRS = keepWarmMod;
    };

    home.activation.herdrKeepWarmMod = lib.mkIf config.custom.claude-code.enable (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run rm -rf "$HOME/.claude/herdr-mods/keep-warm"
        run mkdir -p "$HOME/.claude/herdr-mods"
        run cp -R --no-preserve=mode ${./claude-mods/keep-warm} "$HOME/.claude/herdr-mods/keep-warm"
      ''
    );

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

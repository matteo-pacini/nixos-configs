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
in
{
  options.custom.herdr = {
    enable = lib.mkEnableOption "herdr-core (`hc`), the server that runs Herdr's terminals and agents";
    desktop = lib.mkEnableOption "the Herdr desktop app";
  };

  config = lib.mkIf cfg.enable {
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
          { hooks = [ { type = "command"; command = "${lib.getExe claudeSession} start"; } ]; }
        ];
        SessionEnd = [
          { hooks = [ { type = "command"; command = "${lib.getExe claudeSession} end"; } ]; }
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
  };
}

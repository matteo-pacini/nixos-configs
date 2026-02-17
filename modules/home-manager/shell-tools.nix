{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.shell-tools;
in
{
  options.custom.shell-tools = {
    enable = lib.mkEnableOption "Shell productivity tools (direnv, zoxide, fzf, bat, ripgrep)";
    fzf.batPreview = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable bat preview in fzf";
    };
    bat.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable bat";
    };
    ripgrep.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable ripgrep";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      programs.direnv = {
        enable = true;
        enableZshIntegration = true;
        nix-direnv.enable = true;
      };
      programs.zoxide = {
        enable = true;
        enableZshIntegration = true;
      };
      programs.fzf = {
        enable = true;
        enableZshIntegration = true;
      };
    }
    (lib.mkIf cfg.fzf.batPreview {
      programs.fzf.defaultOptions = [ "--preview 'bat --color=always {}'" ];
    })
    (lib.mkIf cfg.bat.enable {
      programs.bat.enable = true;
    })
    (lib.mkIf cfg.ripgrep.enable {
      programs.ripgrep.enable = true;
    })
  ]);
}

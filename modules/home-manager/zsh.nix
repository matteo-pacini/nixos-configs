{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.zsh;
in
{
  options.custom.zsh = {
    enable = lib.mkEnableOption "Zsh configuration";
    powerlevel10k = {
      enable = lib.mkEnableOption "Powerlevel10k zsh theme";
      configSource = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to .p10k.zsh config file";
      };
    };
    suggestionAliases = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable suggestion toggle aliases (suggestions_off/suggestions_on)";
    };
    darwinAliases = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Darwin-specific aliases (eza ls, reloadDock)";
    };
    extraAliases = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Additional shell aliases";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      programs.zsh = {
        enable = true;
        enableCompletion = true;
        autosuggestion.enable = true;
        syntaxHighlighting.enable = true;
        shellAliases = {
          nix-gc = ''
            nix-collect-garbage --delete-old;
            sudo nix-collect-garbage --delete-old;
            nix-store --optimize -v;
          '';
        } // cfg.extraAliases;
      };
    }
    (lib.mkIf cfg.suggestionAliases {
      programs.zsh.shellAliases = {
        suggestions_off = "ZSH_AUTOSUGGEST_HISTORY_IGNORE=*";
        suggestions_on = "unset ZSH_AUTOSUGGEST_HISTORY_IGNORE";
      };
    })
    (lib.mkIf cfg.powerlevel10k.enable {
      programs.zsh.plugins = [
        {
          name = "powerlevel10k";
          src = pkgs.zsh-powerlevel10k;
          file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
        }
      ];
      programs.zsh.initContent = lib.mkIf (cfg.powerlevel10k.configSource != null) ''
        source ~/.p10k.zsh
      '';
      home.file.".p10k.zsh" = lib.mkIf (cfg.powerlevel10k.configSource != null) {
        source = cfg.powerlevel10k.configSource;
      };
    })
    (lib.mkIf cfg.darwinAliases {
      programs.zsh.shellAliases = {
        ls = "${pkgs.eza}/bin/${pkgs.eza.meta.mainProgram} --icons --color=always";
        reloadDock = ''
          defaults write com.apple.dock ResetLaunchPad -bool true;
          killall Dock;
          defaults write com.apple.dock ResetLaunchPad -bool false
        '';
      };
    })
  ]);
}

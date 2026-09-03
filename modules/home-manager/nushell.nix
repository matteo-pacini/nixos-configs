{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.nushell;
in
{
  options.custom.nushell = {
    enable = lib.mkEnableOption "Nushell, launched on demand from the login shell";
    carapace = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Use carapace as the external command completer";
    };
    darwinAliases = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Darwin-specific commands (reloadDock)";
    };
    extraAliases = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Additional shell aliases";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        programs.nushell = {
          enable = true;

          # `ls` stays Nushell's structured builtin; eza gets its own name.
          shellAliases = {
            ll = "${lib.getExe pkgs.eza} --icons --color=always";
          }
          // cfg.extraAliases;

          settings = {
            # Colours resolvable and unresolvable externals differently, the way
            # zsh-syntax-highlighting does. Off by default.
            highlight_resolved_externals = true;
          };

          # An `alias` body is a single expression, so this has to be a `def`.
          extraConfig = ''
            def nix-gc [] {
              nix-collect-garbage --delete-old
              sudo nix-collect-garbage --delete-old
              nix-store --optimize -v
            }
          '';
        };
      }
      (lib.mkIf cfg.carapace {
        programs.carapace.enable = true;
      })
      (lib.mkIf cfg.darwinAliases {
        programs.nushell.extraConfig = ''
          def reloadDock [] {
            defaults write com.apple.dock ResetLaunchPad -bool true
            killall Dock
            defaults write com.apple.dock ResetLaunchPad -bool false
          }
        '';
      })
    ]
  );
}

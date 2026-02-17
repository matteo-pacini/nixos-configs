{ config, pkgs, ... }:
{
  custom.git = {
    enable = true;
    diffMergeTool = "nvimdiff";
    signing = {
      enable = true;
      allowedSignersContent = ''
        * ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO+saZuvP72LcanCjTiXxPcGDBG7of8AJ2gxw/8o1rvI
      '';
    };
    extraAliases = {
      clean-safe-dr = "clean -xdnf -e /.direnv/ -e /.envrc -e /nix/";
      clean-safe = "clean -xdf -e /.direnv/ -e /.envrc -e /nix/";
    };
    includes = [
      {
        contents = {
          core.excludesfile = pkgs.writeText ".gitignore" ''
            /.direnv/
            /.envrc
            /nix/
            /.android
            /.gradle
          '';
        };
        condition = "gitdir:${config.home.homeDirectory}/Repositories/blue-skies/";
      }
      {
        contents = {
          core.excludesfile = pkgs.writeText ".gitignore" ''
            /.direnv/
            /.envrc
            /nix/
          '';
        };
        condition = "gitdir:${config.home.homeDirectory}/Repositories/consumer-app-ios-v3/";
      }
    ];
  };

  custom.ssh = {
    enable = true;
    extraConfig = ''
      AddKeysToAgent yes
      UseKeychain yes
      IdentitiesOnly yes
    '';
    identitiesOnly = false;
    nexus.enable = true;
    github.enable = true;
  };
}

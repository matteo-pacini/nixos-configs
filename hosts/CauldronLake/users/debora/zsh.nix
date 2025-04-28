{ pkgs, ... }:
{
  programs.zsh = {
    initContent = ''
      source ~/.p10k.zsh
    '';
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
      {
        name = "zsh-history-substring-search";
        src = pkgs.zsh-history-substring-search;
      }
    ];
    shellAliases = {
      nix-gc = ''
        nix-collect-garbage --delete-old;
        sudo nix-collect-garbage --delete-old;
        nix-store --optimize -v;
      '';
      update = ''
        cd /etc/nixos;
        git reset --hard;
        git clean -xdf;
        git pull;
        sudo nixos-rebuild boot;
        echo "Update complete, please reboot the computer";
      '';
    };
  };
}

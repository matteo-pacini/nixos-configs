{
  pkgs,
  ...
}:
{
  imports = [

    ./gnome.nix
    ../../../shared/home-manager/firefox.nix
    ./zsh.nix
  ];

  home.username = "antonella";
  home.homeDirectory = "/home/antonella";

  home.packages = with pkgs; [
    #Gnome
    gnomeExtensions.appindicator
    gnome-tweaks
    # Development
    gh
    # Other
    nix-output-monitor
  ];

  home.stateVersion = "23.11";

  programs.firefox.languagePacks = [ "it" ];

  programs.home-manager.enable = true;
}

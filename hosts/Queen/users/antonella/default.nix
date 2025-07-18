{
  pkgs,
  ...
}:
{
  imports = [

    ./gnome.nix
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

  # Firefox configuration
  programs.firefox.languagePacks = [ "it" ];

  # Enable Firefox customization module
  programs.firefox.customization = {
    enable = true;

    history.enable = true;

    # Enable GNOME theme on Linux
    gnomeTheme.enable = true;

    # Enable search engines
    search = {
      nixPackages.enable = false;
      nixOptions.enable = false;
      nixCodeSearch.enable = false;
    };

    # Enable extensions
    extensions = {
      enable = true;
      ublock.enable = true;
      onepassword.enable = false;
    };
  };

  programs.home-manager.enable = true;
}

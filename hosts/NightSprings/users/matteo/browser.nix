{ ... }:
{
  programs.firefox.customization = {
    enable = true;

    gnomeTheme.enable = false;

    history.enable = true;

    # Enable search engines
    search = {
      nixPackages.enable = true;
      nixOptions.enable = true;
      kagi = {
        enable = true;
        setAsDefault = true;
      };
    };

    # Enable extensions
    extensions = {
      enable = true;
      ublock.enable = true;
      onepassword.enable = true;
      dracula.enable = true;
    };
  };
}

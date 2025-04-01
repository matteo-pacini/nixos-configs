{ ... }:
{
  programs.firefox.customization = {
    enable = true;

    gnomeTheme.enable = true;

    # Enable search engines
    search = {
      nixPackages.enable = false;
      nixOptions.enable = false;
      kagi = {
        enable = false;
        setAsDefault = false;
      };
    };

    # Enable extensions
    extensions = {
      enable = true;
      ublock.enable = true;
      onepassword.enable = true;
      dracula.enable = false;
    };
  };
}

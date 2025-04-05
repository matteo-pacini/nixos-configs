{ ... }:
{
  programs.firefox.customization = {
    enable = true;

    gnomeTheme.enable = true;

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
    };
  };
}

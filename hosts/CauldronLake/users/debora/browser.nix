{ ... }:
{
  programs.firefox.customization = {
    enable = true;

    gnomeTheme.enable = true;

    history.enable = true;

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
      onepassword.enable = true;
    };
  };
}

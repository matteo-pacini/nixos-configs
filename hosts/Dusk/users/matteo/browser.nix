{ ... }:
{
  programs.firefox.customization = {
    enable = true;

    gnomeTheme.enable = false;

    # Enable search engines
    search = {
      nixPackages.enable = true;
      nixOptions.enable = true;
      nixCodeSearch.enable = true;
    };

    # Enable extensions
    extensions = {
      enable = true;
      ublock.enable = true;
      onepassword.enable = true;
    };
  };
}

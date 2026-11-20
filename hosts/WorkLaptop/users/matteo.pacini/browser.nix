{ ... }:
{
  programs.firefox.customization = {
    enable = true;

    gnomeTheme.enable = false;

    history.enable = true;

    search = {
      nixPackages.enable = true;
      nixOptions.enable = true;
      nixCodeSearch.enable = true;
    };

    extensions = {
      enable = true;
      ublock.enable = true;
      onepassword.enable = true;
      violentmonkey.enable = true;
    };
  };
}

{ ... }:
{
  programs.firefox.customization = {
    enable = true;

    gnomeTheme.enable = true;

    history.enable = true;

    search = {
      nixPackages.enable = false;
      nixOptions.enable = false;
      nixCodeSearch.enable = false;
    };

    extensions = {
      enable = true;
      ublock.enable = true;
      onepassword.enable = true;
    };
  };
}

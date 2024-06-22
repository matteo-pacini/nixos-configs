{ pkgs, ... }:
{
  programs.firefox = {
    enable = true;
    package = pkgs.firefox-app;
    profiles = {
      default = {
        id = 0;
        name = "Default";
        isDefault = true;
        search = {
          default = "DuckDuckGo";
          force = true;
          engines = {
            "Nix Packages" = {
              urls = [
                {
                  template = "https://search.nixos.org/packages";
                  params = [
                    {
                      name = "type";
                      value = "packages";
                    }
                    {
                      name = "query";
                      value = "{searchTerms}";
                    }
                  ];
                }
              ];
              icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
              definedAliases = [ "@np" ];
            };
          };
        };

        # https://github.com/nix-community/nur-combined/blob/master/repos/rycee/pkgs/firefox-addons/generated-firefox-addons.nix
        extensions = [ ];
      };
    };
  };
}

{
  pkgs,
  inputs,
  lib,
  ...
}:
let
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
in
{
  home.file = lib.optionalAttrs isLinux {
    ".mozilla/firefox/default/chrome/firefox-gnome-theme".source = inputs.firefox-gnome-theme;
  };

  programs.firefox = {
    enable = true;
    package = if pkgs.stdenv.isDarwin then pkgs.firefox-bin else pkgs.firefox;
    profiles = {
      default = {
        id = 0;
        name = "Default";
        isDefault = true;
        search = {
          default = "Kagi";
          privateDefault = "ddg";
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
                      name = "channel";
                      value = "unstable";
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
            "Nix Options" = {
              urls = [
                {
                  template = "https://search.nixos.org/options";
                  params = [
                    {
                      name = "type";
                      value = "packages";
                    }
                    {
                      name = "channel";
                      value = "unstable";
                    }
                    {
                      name = "query";
                      value = "{searchTerms}";
                    }
                  ];
                }
              ];
              icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
              definedAliases = [ "@no" ];
            };
            "Kagi" = {
              urls = [
                {
                  template = "https://kagi.com/search";
                  params = [
                    {
                      name = "q";
                      value = "{searchTerms}";
                    }
                  ];
                }
              ];
              icon = "https://kagi.com/asset/v2/favicon-16x16.png";
              definedAliases = [ "@k" ];
            };
          };
        };
        userChrome = lib.optionalString isLinux ''
          @import "firefox-gnome-theme/userChrome.css";
        '';
        userContent = lib.optionalString isLinux ''
          @import "firefox-gnome-theme/userContent.css";
        '';
        settings = lib.mkMerge [
          (lib.mkIf isLinux {
            #########################
            ## Firefox gnome theme ##
            #########################
            "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
            "browser.uidensity" = 0;
            "svg.context-properties.content.enabled" = true;
            "browser.theme.dark-private-windows" = false;
          })
        ];

        # https://github.com/nix-community/nur-combined/blob/master/repos/rycee/pkgs/firefox-addons/generated-firefox-addons.nix
        extensions.packages =
          with pkgs.nur.repos.rycee.firefox-addons;
          [
            ublock-origin
            onepassword-password-manager
          ]
          ++ lib.optionals isDarwin [ dracula-dark-colorscheme ];
      };
    };
  };
}

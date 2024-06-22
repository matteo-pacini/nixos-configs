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
    package = if pkgs.stdenv.isDarwin then pkgs.firefox-app else pkgs.unstable.firefox;
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
        extensions =
          if pkgs.stdenv.hostPlatform.system == "x86_64-darwin" then
            # TODO: Investigate why the NUR doesn't evaluate on Intel Macs
            [ ]
          else
            with pkgs.nur.repos.rycee.firefox-addons;
            [
              ublock-origin
              darkreader
              onepassword-password-manager
              istilldontcareaboutcookies
            ]
            ++ lib.optionals isDarwin [ dracula-dark-colorscheme ];
      };
    };
  };
}

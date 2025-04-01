{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    types
    ;
  cfg = config.programs.firefox.customization;
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
in
{
  options.programs.firefox.customization = {
    enable = mkEnableOption "Firefox customization";

    gnomeTheme = {
      enable = mkEnableOption "GNOME theme integration for Firefox";
    };

    search = {
      nixPackages = {
        enable = mkEnableOption "Nix Packages search engine";
      };

      nixOptions = {
        enable = mkEnableOption "Nix Options search engine";
      };

      kagi = {
        enable = mkEnableOption "Kagi search engine";
        setAsDefault = mkEnableOption "Set Kagi as the default search engine";
      };
    };

    extensions = {
      enable = mkEnableOption "Firefox extensions";

      dracula = {
        enable = mkEnableOption "Dracula theme for Firefox (Darwin only)";
      };

      ublock = {
        enable = mkEnableOption "uBlock Origin extension";
      };

      onepassword = {
        enable = mkEnableOption "1Password extension";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # Base Firefox configuration
    {
      programs.firefox = {
        enable = true;
        package = if isDarwin then pkgs.firefox-bin else pkgs.firefox;
        profiles = {
          default = {
            id = 0;
            name = "Default";
            isDefault = true;
            search = {
              force = true;
              privateDefault = "ddg";
            };
          };
        };
      };
    }

    # GNOME theme (Linux only)
    (mkIf (cfg.gnomeTheme.enable && isLinux) {
      home.file.".mozilla/firefox/default/chrome/firefox-gnome-theme".source = inputs.firefox-gnome-theme;

      programs.firefox.profiles.default = {
        userChrome = ''
          @import "firefox-gnome-theme/userChrome.css";
        '';

        userContent = ''
          @import "firefox-gnome-theme/userContent.css";
        '';

        settings = {
          "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
          "browser.uidensity" = 0;
          "svg.context-properties.content.enabled" = true;
          "browser.theme.dark-private-windows" = false;
        };
      };
    })

    # Nix Packages search engine
    (mkIf cfg.search.nixPackages.enable {
      programs.firefox.profiles.default.search.engines = {
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
      };
    })

    # Nix Options search engine
    (mkIf cfg.search.nixOptions.enable {
      programs.firefox.profiles.default.search.engines = {
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
      };
    })

    # Kagi search engine
    (mkIf cfg.search.kagi.enable {
      programs.firefox.profiles.default.search.engines = {
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
    })

    # Set Kagi as default search engine if enabled
    (mkIf (cfg.search.kagi.enable && cfg.search.kagi.setAsDefault) {
      programs.firefox.profiles.default.search.default = "Kagi";
    })

    # Extensions
    (mkIf cfg.extensions.enable {
      programs.firefox.profiles.default.extensions.packages = mkMerge [
        (mkIf cfg.extensions.ublock.enable [ pkgs.nur.repos.rycee.firefox-addons.ublock-origin ])
        (mkIf cfg.extensions.onepassword.enable [
          pkgs.nur.repos.rycee.firefox-addons.onepassword-password-manager
        ])
        (mkIf (cfg.extensions.dracula.enable && isDarwin) [
          pkgs.nur.repos.rycee.firefox-addons.dracula-dark-colorscheme
        ])
      ];
    })
  ]);
}

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
    ;
  cfg = config.programs.firefox.customization;
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
in
{
  options.programs.firefox.customization = {
    enable = mkEnableOption "Firefox customization";

    gnomeTheme = {
      enable = mkEnableOption "GNOME theme integration for Firefox";
    };

    history = {
      enable = mkEnableOption "Enables history tracking";
    };

    search = {
      nixPackages = {
        enable = mkEnableOption "Nix Packages search engine";
      };

      nixOptions = {
        enable = mkEnableOption "Nix Options search engine";
      };

      nixCodeSearch = {
        enable = mkEnableOption "Nix Code Search on GitHub";
      };

    };

    extensions = {
      enable = mkEnableOption "Firefox extensions";

      ublock = {
        enable = mkEnableOption "uBlock Origin extension";
      };

      onepassword = {
        enable = mkEnableOption "1Password extension";
      };

      violentmonkey = {
        enable = mkEnableOption "Violentmonkey extension";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # Base Firefox configuration
    {
      programs.firefox = {
        enable = true;
        package = pkgs.firefox;
        # Pin: HM 26.05's Linux default flipped to ~/.config/mozilla/firefox,
        # but stock pkgs.firefox still reads ~/.mozilla/firefox. Darwin keeps
        # HM's default (Library/Application Support/Firefox).
        configPath = mkIf isLinux ".mozilla/firefox";
        profiles = {
          default = {
            id = 0;
            name = "Default";
            isDefault = true;
            search = {
              force = true;
              default = "ddg";
            };
            settings = {
              "places.history.enabled" = cfg.history.enable;
              "browser.chrome.site_icons" = true;

              # Sponsored content & new-tab "Popular today / Health / Entertainment"
              "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
              "browser.newtabpage.activity-stream.showSponsored" = false;
              "browser.newtabpage.activity-stream.feeds.section.topstories" = false;
              "browser.newtabpage.activity-stream.showSponsoredCheckboxes" = false;
              "browser.newtabpage.activity-stream.default.sites" = "";

              # Telemetry
              "datareporting.policy.dataSubmissionEnabled" = false;
              "datareporting.healthreport.uploadEnabled" = false;
              "datareporting.usage.uploadEnabled" = false;
              "toolkit.telemetry.unified" = false;
              "toolkit.telemetry.enabled" = false;
              "toolkit.telemetry.server" = "data:,";
              "toolkit.telemetry.archive.enabled" = false;
              "toolkit.telemetry.newProfilePing.enabled" = false;
              "toolkit.telemetry.shutdownPingSender.enabled" = false;
              "toolkit.telemetry.updatePing.enabled" = false;
              "toolkit.telemetry.bhrPing.enabled" = false;
              "toolkit.telemetry.firstShutdownPing.enabled" = false;
              "toolkit.telemetry.coverage.opt-out" = true;
              "toolkit.coverage.opt-out" = true;
              "toolkit.coverage.endpoint.base" = "";
              "browser.newtabpage.activity-stream.feeds.telemetry" = false;
              "browser.newtabpage.activity-stream.telemetry" = false;

              # Studies / experiments (Normandy, Shield)
              "app.shield.optoutstudies.enabled" = false;
              "app.normandy.enabled" = false;
              "app.normandy.api_url" = "";

              # Crash reports
              "breakpad.reportURL" = "";
              "browser.tabs.crashReporting.sendReport" = false;

              # CFR & personalized add-on recommendations
              "browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons" = false;
              "browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features" = false;
              "browser.discovery.enabled" = false;
              "extensions.htmlaboutaddons.recommendations.enabled" = false;
              "extensions.getAddons.showPane" = false;
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

    # Nix Code Search engine
    (mkIf cfg.search.nixCodeSearch.enable {
      programs.firefox.profiles.default.search.engines = {
        "Nix Code Search" = {
          urls = [
            {
              template = "https://github.com/search";
              params = [
                {
                  name = "q";
                  value = "repo:nixos/nixpkgs language:nix {searchTerms}";
                }
                {
                  name = "type";
                  value = "code";
                }
              ];
            }
          ];
          icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
          definedAliases = [ "@ncs" ];
        };
      };
    })

    # Extensions
    (mkIf cfg.extensions.enable {
      programs.firefox.profiles.default.extensions.packages = mkMerge [
        (mkIf cfg.extensions.ublock.enable [ pkgs.nur.repos.rycee.firefox-addons.ublock-origin ])
        (mkIf cfg.extensions.onepassword.enable [
          pkgs.nur.repos.rycee.firefox-addons.onepassword-password-manager
        ])
        (mkIf cfg.extensions.violentmonkey.enable [
          pkgs.nur.repos.rycee.firefox-addons.violentmonkey
        ])
      ];
    })
  ]);
}

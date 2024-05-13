{
  config,
  pkgs,
  inputs,
  lib,
  ...
}: {
  programs.firefox = {
    enable = true;
    package =
      if pkgs.stdenv.isDarwin
      then pkgs.firefox-app
      else pkgs.unstable.firefox;
    profiles = {
      matteo = {
        id = 0;
        name = "Matteo";
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
              definedAliases = ["@np"];
            };
            "Github" = {
              urls = [
                {
                  template = "https://github.com/search";
                  params = [
                    {
                      name = "type";
                      value = "code";
                    }
                    {
                      name = "q";
                      value = "{searchTerms}";
                    }
                  ];
                }
              ];
              definedAliases = ["@gh"];
            };
          };
        };
        settings = {
          # Firefox View
          "browser.tabs.firefox-view" = false;
          "browser.tabs.firefox-view-next" = false;
          # Mozilla telemetry
          "browser.newtabpage.activity-stream.feeds.telemetry" = false;
          "browser.newtabpage.activity-stream.telemetry" = false;
          "browser.ping-centre.telemetry" = false;
          "toolkit.telemetry.archive.enabled" = false;
          "toolkit.telemetry.bhrPing.enabled" = false;
          "toolkit.telemetry.enabled" = false;
          "toolkit.telemetry.firstShutdownPing.enabled" = false;
          "toolkit.telemetry.hybridContent.enabled" = false;
          "toolkit.telemetry.newProfilePing.enabled" = false;
          "toolkit.telemetry.reportingpolicy.firstRun" = false;
          "toolkit.telemetry.shutdownPingSender.enabled" = false;
          "toolkit.telemetry.unified" = false;
          "toolkit.telemetry.updatePing.enabled" = false;
          # Addon recomendations
          "browser.discovery.enabled" = false;
          "extensions.getAddons.showPane" = false;
          "extensions.htmlaboutaddons.recommendations.enabled" = false;
          # Experiments
          "experiments.activeExperiment" = false;
          "experiments.enabled" = false;
          "experiments.supported" = false;
          "network.allow-experiments" = false;
          # Pocket & Other Sponsored Content
          "extensions.pocket.enabled" = false;
          "extensions.pocket.showHome" = false;
          "browser.newtabpage.activity-stream.feeds.discoverystreamfeed" = false;
          "browser.newtabpage.activity-stream.feeds.section.topstories" = false;
          "browser.newtabpage.activity-stream.section.highlights.includePocket" = false;
          "browser.newtabpage.activity-stream.showSponsored" = false;
          "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
          "browser.newtabpage.activity-stream.system.showSponsored" = false;
          # Block updates
          "extensions.update.enabled" = false;
          # Privacy
          "privacy.donottrackheader.enabled" = true;
          "signon.rememberSignons" = false;
          # Harden SSL
          "security.ssl.require_safe_negotiation" = true;
          # Disable JS in PDFs
          "pdfjs.enableScripting" = false;
          # Other
          "browser.aboutConfig.showWarning" = false;
        };
        # https://github.com/nix-community/nur-combined/blob/master/repos/rycee/pkgs/firefox-addons/generated-firefox-addons.nix
        extensions = with pkgs.nur.repos.rycee.firefox-addons;
          [
            ublock-origin
            darkreader
            onepassword-password-manager
            istilldontcareaboutcookies
          ]
          ++ lib.optionals (pkgs.stdenv.isDarwin) [
            dracula-dark-colorscheme
          ];
      };
    };
  };
}

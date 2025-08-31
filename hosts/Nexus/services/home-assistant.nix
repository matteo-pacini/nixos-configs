{ pkgs, ... }:
{
  services.home-assistant = {
    enable = true;
    extraComponents = [
      # Components required to complete the onboarding
      "analytics"
      "google_translate"
      "met"
      "radio_browser"
      "shopping_list"
      # Recommended for fast zlib compression
      # https://www.home-assistant.io/integrations/isal
      "isal"
      # Zigbee
      "mqtt"
      # Printer
      "ipp"
      "brother"
      # Unifi
      "unifi"
      # Wake on LAN
      "wake_on_lan"
      # Ping
      "ping"
      # Shield
      "androidtv"
      # LG TV
      "webostv"
      # Shell commands
      "shell_command"
      # UPS
      "apcupsd"
    ];
    customComponents = with pkgs.home-assistant-custom-components; [
      waste_collection_schedule
      smartthinq-sensors
      (volvo_cars.overrideAttrs (old: {
        version = "1.5.6";
        src = pkgs.fetchFromGitHub {
          owner = "thomasddn";
          repo = "ha-volvo-cars";
          rev = "v1.5.6";
          hash = "sha256-2eTUIbwAadJsOp1ETDY6+cEPVMOzhj1otEyzobysqaY=";
        };
      }))
      (pkgs.callPackage pkgs.buildHomeAssistantComponent rec {
        owner = "BottlecapDave";
        domain = "octopus_energy";
        version = "16.0.0";

        src = pkgs.fetchFromGitHub {
          inherit owner;
          repo = "HomeAssistant-OctopusEnergy";
          rev = "v${version}";
          sha256 = "sha256-cUegQT/oYkRKoLBTa6e0wL7BkRU+jzypzsKjJs5okvk=";
        };

        doCheck = false;
      })
    ];
    customLovelaceModules = with pkgs.home-assistant-custom-lovelace-modules; [
      card-mod
      bubble-card
      sankey-chart
      mushroom
      mini-graph-card
    ];
    extraPackages =
      python3Packages: with python3Packages; [
        psycopg2
        pyatv
        pyipp
      ];

    config = {
      # Includes dependencies for a basic setup
      # https://www.home-assistant.io/integrations/default_config/
      default_config = { };

      homeassistant = {
        name = "Frenches Farm Drive 49 HASS";
        unit_system = "metric";
        currency = "GBP";
        time_zone = "Europe/London";
        external_url = "https://home.matteopacini.me";
        internal_url = "http://nexus.home.internal:8123";
      };

      shell_command = { };

      recorder = {
        db_url = "postgresql://@/hass";
        purge_keep_days = 10;
      };

      http = {
        use_x_forwarded_for = true;
        server_host = "0.0.0.0";
        server_port = 8123;
        trusted_proxies = [ "127.0.0.1" ];
        ip_ban_enabled = true;
        login_attempts_threshold = 5;
      };

      frontend = {
        themes = "!include_dir_merge_named themes";
      };

      lovelace.mode = "yaml";

      "automation ui" = "!include automations.yaml";
      "scene ui" = "!include scenes.yaml";
      "script ui" = "!include scripts.yaml";

    };
  };

  systemd.services.home-assistant.preStart = ''
    touch /var/lib/hass/automations.yaml
    touch /var/lib/hass/scenes.yaml
    touch /var/lib/hass/scripts.yaml
  '';

  services.postgresql = {
    enable = true;
    ensureDatabases = [ "hass" ];
    ensureUsers = [
      {
        name = "hass";
        ensureDBOwnership = true;
      }
    ];
  };

  services.victoriametrics.enable = true;
  services.victorialogs.enable = true;

}

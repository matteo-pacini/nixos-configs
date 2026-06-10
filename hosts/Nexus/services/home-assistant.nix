{ pkgs, ... }:
let
  systemctl = "${pkgs.systemd}/bin/systemctl";
in
{
  # Allow hass user to restart specific services via polkit (no sudo needed).
  # This is more secure than using sudo as it doesn't require disabling
  # systemd's security hardening (NoNewPrivileges, RestrictSUIDSGID, etc.)
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          (action.lookup("unit") == "zigbee2mqtt.service" ||
           action.lookup("unit") == "mosquitto.service") &&
          subject.user == "hass") {
        return polkit.Result.YES;
      }
    });
  '';

  services.home-assistant = {
    enable = true;
    openFirewall = true;
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
      "unifiprotect"
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
      # Voice
      "whisper"
      "piper"
      "wake_word"
      "wyoming"
      # Shelly
      "shelly"
      # SmartThings
      "smartthings"
    ];
    customComponents = with pkgs.home-assistant-custom-components; [
      waste_collection_schedule
      smartthinq-sensors
      volvo_cars
      octopus_energy
      localtuya
      (pkgs.buildHomeAssistantComponent rec {
        owner = "eulemitkeule";
        domain = "webhook_conversation";
        version = "1.12.1";

        src = pkgs.fetchFromGitHub {
          inherit owner;
          repo = "webhook-conversation";
          tag = "${version}";
          hash = "sha256-gTrid3Wa2s9jIYkdHzRYz4tHd4WrbZ63vhlb6kqTJCk=";
        };

        dependencies = with pkgs.home-assistant.python3Packages; [
          voluptuous-openapi
        ];

      })
      (pkgs.buildHomeAssistantComponent rec {
        owner = "nielsfaber";
        domain = "scheduler";
        version = "3.3.8";

        src = pkgs.fetchFromGitHub {
          inherit owner;
          repo = "scheduler-component";
          tag = "v${version}";
          hash = "sha256-QN7rkNuj9IBbV2ths7ZdL/EkXFJUpjNbgJNUnAHjLBA=";
        };
      })
    ];
    customLovelaceModules = with pkgs.home-assistant-custom-lovelace-modules; [
      card-mod
      bubble-card
      sankey-chart
      mushroom
      mini-graph-card
      button-card
      # In nixpkgs master but not yet in our pin; drop this inline copy
      # once the pin advances past NixOS/nixpkgs#525127.
      (pkgs.buildNpmPackage rec {
        pname = "trash-card";
        version = "2.4.7";

        src = pkgs.fetchFromGitHub {
          owner = "idaho";
          repo = "hassio-trash-card";
          tag = version;
          hash = "sha256-Zf+iUcJs45eguaDJcuto6ccc/puormFajmYMc7Qpdsw=";
        };

        npmDepsHash = "sha256-zvsJASztDfecn+FRvQPmT0vIblaCD11eBM9LLq+VFrg=";

        installPhase = ''
          runHook preInstall

          mkdir $out
          cp dist/trashcard.js $out/

          runHook postInstall
        '';

        passthru.entrypoint = "trashcard.js";
      })
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

      # Service status monitoring
      command_line = [
        {
          binary_sensor = {
            name = "Zigbee2MQTT Running";
            command = "${pkgs.systemd}/bin/systemctl is-active zigbee2mqtt";
            payload_on = "active";
            payload_off = "inactive";
            device_class = "running";
            scan_interval = 5;
          };
        }
        {
          binary_sensor = {
            name = "Mosquitto Running";
            command = "${pkgs.systemd}/bin/systemctl is-active mosquitto";
            payload_on = "active";
            payload_off = "inactive";
            device_class = "running";
            scan_interval = 5;
          };
        }
      ];

      homeassistant = {
        name = "Frenches Farm Drive 49 HASS";
        unit_system = "metric";
        currency = "GBP";
        time_zone = "Europe/London";
        external_url = "https://home.matteopacini.me";
        internal_url = "http://nexus.home.internal:8123";
        allowlist_external_dirs = [
          "/tmp"
          "/var/lib/hass/www"
        ];
      };

      shell_command = {
        restart_zigbee2mqtt = "${systemctl} restart zigbee2mqtt";
        restart_mosquitto = "${systemctl} restart mosquitto";
      };

      logger = {
        default = "info";
        logs."homeassistant.components.http.ban" = "warning";
      };

      recorder = {
        db_url = "postgresql://@/hass";
        purge_keep_days = 365;
        auto_purge = true;
        auto_repack = true;
        exclude = {
          domains = [
            "automation"
            "script"
          ];
          entity_globs = [
            "sensor.clock*"
            "sensor.date*"
            "sensor.glances*"
            "sensor.time*"
            "sensor.uptime*"
            "sensor.dwd_weather_warnings_*"
            "weather.weatherstation"
            "binary_sensor.*_smartphone_*"
            "sensor.*_smartphone_*"
            "sensor.adguard_home_*"
            "binary_sensor.*_internet_access"
          ];
        };
      };

      http = {
        use_x_forwarded_for = true;
        server_host = "0.0.0.0";
        server_port = 8123;
        trusted_proxies = [ "127.0.0.1" ];
        # Disable built-in IP banning - handled by fail2ban instead
        ip_ban_enabled = false;
      };

      frontend = {
        themes = "!include_dir_merge_named themes";
      };

      lovelace = {
        resource_mode = "yaml";
        dashboards.lovelace = {
          mode = "yaml";
          filename = "ui-lovelace.yaml";
          title = "Overview";
          icon = "mdi:view-dashboard";
          show_in_sidebar = true;
        };
      };

      "automation ui" = "!include automations.yaml";
      "scene ui" = "!include scenes.yaml";
      "script ui" = "!include scripts.yaml";

    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/hass/www 0755 hass hass"
  ];

  systemd.services.home-assistant.preStart = ''
    touch /var/lib/hass/automations.yaml
    touch /var/lib/hass/scenes.yaml
    touch /var/lib/hass/scripts.yaml
  '';

  services = {
    wyoming = {
      faster-whisper = {
        package = pkgs.wyoming-faster-whisper;
        servers.ha = {
          enable = true;
          uri = "tcp://0.0.0.0:10300";
          language = "en";
        };
      };

      piper.servers.ha = {
        enable = true;
        uri = "tcp://0.0.0.0:10200";
        voice = "en_GB-alan-medium";
      };
    };
  };

}

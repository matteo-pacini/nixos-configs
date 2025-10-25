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
      # Timeseries database
      "influxdb"
      # Voice
      "whisper"
      "piper"
      "wake_word"
      "wyoming"
    ];
    customComponents = with pkgs.home-assistant-custom-components; [
      waste_collection_schedule
      smartthinq-sensors
      volvo_cars
      octopus_energy
      localtuya
      (pkgs.buildHomeAssistantComponent rec {
        owner = "jekalmin";
        domain = "extended_openai_conversation";
        version = "1.0.6-beta1";

        src = pkgs.fetchFromGitHub {
          inherit owner;
          repo = domain;
          tag = "${version}";
          hash = "sha256-4Dty/kHXZNsq/QKQ+az4kaUWoYt9SWvAe9SQag4js4M=";
        };

        propagatedBuildInputs = [ pkgs.openai ];

        ignoreVersionRequirement = [
          "openai"
        ];
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

      influxdb = {
        api_version = 1;
        host = "127.0.0.1";
        port = 8428;
        max_retries = 3;
        measurement_attr = "entity_id";
        tags_attributes = [
          "friendly_name"
          "unit_of_measurement"
          "state_class"
          "device_class"
        ];
        ignore_attributes = [
          "icon"
          "source"
          "options"
          "editable"
          "min"
          "max"
          "step"
          "mode"
          "marker_type"
          "preset_modes"
          "supported_features"
          "supported_color_modes"
          "effect_list"
          "attribution"
          "assumed_state"
          "state_open"
          "state_closed"
          "writable"
          "stateExtra"
          "event"
          "ip_address"
          "device_file"
          "unitOfMeasure"
          "color_mode"
          "hs_color"
          "rgb_color"
          "xy_color"
          "hvac_action"
          "value"
          "writeable"
          "attribution"
          "dataCorrect"
          "dayname"
        ];
        include = {
          domains = [
            "sensor"
            "binary_sensor"
            "light"
            "switch"
            "cover"
            "climate"
            "input_boolean"
            "input_select"
            "number"
            "lock"
            "weather"
          ];
        };
        exclude = {
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

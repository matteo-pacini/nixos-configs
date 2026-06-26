{ pkgs, ... }:
let
  systemctl = "${pkgs.systemd}/bin/systemctl";
  ipmitool = "${pkgs.ipmitool}/bin/ipmitool";

  # Dell PowerEdge R730xd iDRAC OEM fan control (raw 0x30 0x30 ...). These
  # opcodes are write-only — the BMC won't report the duty/mode back — so HA
  # owns the setpoint (input_number/input_select below) and reads real fan RPM
  # via the command_line sensor as ground-truth feedback. hass reaches
  # /dev/ipmi0 through the "ipmi" group + DeviceAllow exception (no sudo).
  fanSet = pkgs.writeShellScript "nexus-fan-set" ''
    ${ipmitool} raw 0x30 0x30 0x01 0x00
    ${ipmitool} raw 0x30 0x30 0x02 0xff "$(printf '0x%02x' "$1")"
  '';
  fanAuto = pkgs.writeShellScript "nexus-fan-auto" ''
    ${ipmitool} raw 0x30 0x30 0x01 0x01
  '';
  fanRpm = pkgs.writeShellScript "nexus-fan-rpm" ''
    ${ipmitool} sdr type fan | ${pkgs.gawk}/bin/awk -F'|' '$5 ~ /RPM/ { gsub(/[^0-9]/, "", $5); s += $5; c++ } END { if (c) printf "%d", s / c }'
  '';
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

  # Fan control: let the hardened hass service reach the Dell BMC at
  # /dev/ipmi0 without sudo. Keeps NoNewPrivileges/RestrictSUIDSGID/
  # ProtectSystem=strict intact; only grants the one device + group.
  users.groups.ipmi = { };
  services.udev.extraRules = ''
    KERNEL=="ipmi*", GROUP="ipmi", MODE="0660"
  '';
  systemd.services.home-assistant.serviceConfig = {
    SupplementaryGroups = [ "ipmi" ];
    DeviceAllow = [ "/dev/ipmi0 rw" ];
  };

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
      # Volvo (core integration, OAuth via Application Credentials)
      "volvo"
    ];
    customComponents = with pkgs.home-assistant-custom-components; [
      waste_collection_schedule
      smartthinq-sensors
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
        {
          sensor = {
            name = "Nexus Fan Speed";
            command = "${fanRpm}";
            unit_of_measurement = "RPM";
            state_class = "measurement";
            icon = "mdi:fan";
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
        # Forces manual mode, then applies the current input_number duty.
        fan_set = "${fanSet} {{ states('input_number.fan_duty') | int }}";
        fan_auto = "${fanAuto}";
      };

      # Fan control state. The Dell BMC can't report duty/mode back, so HA is
      # the source of truth; the "Nexus Fan Speed" sensor is the real readback.
      input_number.fan_duty = {
        name = "Nexus Fan Duty";
        min = 0;
        max = 100;
        step = 10;
        unit_of_measurement = "%";
        icon = "mdi:fan";
        mode = "slider";
      };

      input_select.fan_mode = {
        name = "Nexus Fan Mode";
        options = [
          "auto"
          "manual"
        ];
        icon = "mdi:fan-auto";
      };

      # Duty readout that shows "- %" in auto (the % is meaningless then).
      # input_number can't hold a non-numeric value, so this is a separate
      # display entity; keep input_number as the control (slider/buttons).
      template = [
        {
          sensor = [
            {
              name = "Nexus Fan Duty Display";
              # No unit_of_measurement: with one set, HA treats the sensor as
              # numeric and rejects the "- %" string. Bake the unit in instead.
              state = "{{ '- %' if is_state('input_select.fan_mode', 'auto') else (states('input_number.fan_duty') | int) ~ ' %' }}";
              icon = "mdi:fan";
            }
          ];
        }
      ];

      # Thin nudgers: they only move the helpers. The automations below push
      # helper changes to the BMC, so editing the dropdown/slider directly
      # applies too — no separate "apply" step. Duty is set before mode so a
      # manual switch reads the new value and applies exactly once.
      "script fans" = {
        nexus_fan_increase = {
          alias = "Nexus Fan +10%";
          icon = "mdi:fan-plus";
          sequence = [
            {
              service = "input_number.set_value";
              target.entity_id = "input_number.fan_duty";
              data.value = "{{ [ (states('input_number.fan_duty') | int) + 10, 100 ] | min }}";
            }
            {
              service = "input_select.select_option";
              target.entity_id = "input_select.fan_mode";
              data.option = "manual";
            }
          ];
        };
        nexus_fan_decrease = {
          alias = "Nexus Fan -10%";
          icon = "mdi:fan-minus";
          sequence = [
            {
              service = "input_number.set_value";
              target.entity_id = "input_number.fan_duty";
              data.value = "{{ [ (states('input_number.fan_duty') | int) - 10, 0 ] | max }}";
            }
            {
              service = "input_select.select_option";
              target.entity_id = "input_select.fan_mode";
              data.option = "manual";
            }
          ];
        };
        nexus_fan_auto = {
          alias = "Nexus Fan Auto";
          icon = "mdi:fan-auto";
          sequence = [
            {
              service = "input_select.select_option";
              target.entity_id = "input_select.fan_mode";
              data.option = "auto";
            }
          ];
        };
      };

      # The helpers are the control surface; these push helper changes to the
      # BMC. Flipping the dropdown to manual or moving the slider applies
      # immediately, and a cold-reboot reset (iDRAC reverts to auto) is healed
      # on HA start.
      "automation fans" = [
        {
          alias = "Nexus Fan apply mode (start + change)";
          trigger = [
            {
              platform = "homeassistant";
              event = "start";
            }
            {
              platform = "state";
              entity_id = "input_select.fan_mode";
            }
          ];
          action = [
            {
              choose = [
                {
                  conditions = [
                    {
                      condition = "state";
                      entity_id = "input_select.fan_mode";
                      state = "manual";
                    }
                  ];
                  sequence = [ { service = "shell_command.fan_set"; } ];
                }
              ];
              default = [ { service = "shell_command.fan_auto"; } ];
            }
          ];
        }
        {
          alias = "Nexus Fan apply duty (manual only)";
          trigger = [
            {
              platform = "state";
              entity_id = "input_number.fan_duty";
            }
          ];
          condition = [
            {
              condition = "state";
              entity_id = "input_select.fan_mode";
              state = "manual";
            }
          ];
          action = [ { service = "shell_command.fan_set"; } ];
        }
      ];

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

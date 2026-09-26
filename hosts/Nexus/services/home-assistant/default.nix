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

  # openFirewall reads config.http.server_port, which no longer exists now
  # that the http block moved to UI storage — open the default port directly.
  networking.firewall.allowedTCPPorts = [ 8123 ];

  services.home-assistant = {
    enable = true;

    # Symlinked into ${configDir}/blueprints/automation. Blueprints only supply
    # the template; each automation built from one is still created in the UI
    # and lives in .storage.
    # NOTE: these land flat in blueprints/automation/, whereas the copies HA
    # already has sit under blueprints/automation/matteo-pacini/. Automations
    # built from the old path keep working until they are repointed; nothing
    # here deletes those files (the module only reaps store symlinks at depth 2).
    blueprints.automation = [
      ./blueprints/automation/socket-auto-recover.yaml
      ./blueprints/automation/door_warning_blueprint.yaml
      ./blueprints/automation/sonoff_trvzb_external_temp_sync.yaml
    ];

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
      # Long-term metrics export to VictoriaMetrics (Influx v1 line protocol)
      "influxdb"
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
      # MCP server (exposes Assist-exposed entities at /api/mcp)
      "mcp_server"
      # Subscribes to a remote .ics feed. Configured through the UI, so the
      # feed URL and its API key live in .storage and stay out of this repo.
      "remote_calendar"
    ];
    customComponents = with pkgs.home-assistant-custom-components; [
      waste_collection_schedule
      # Patched so a failed setup raises ConfigEntryNotReady instead of
      # reporting success. See the patch header for why upstream stopped doing
      # that and why the reason does not apply here.
      (smartthinq-sensors.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./patches/smartthinq-sensors-retry-setup.patch ];
      }))
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

        patches = [ ./patches/webhook-conversation-stream-errors.patch ];

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
      clock-weather-card
      # Not in nixpkgs at all. Ships two chunks: the card lazily imports
      # ./editor.js, so both must land in the merged lovelace module dir.
      # No other module here ships an editor.js, so the buildEnv merge is safe.
      (pkgs.buildNpmPackage rec {
        pname = "calendar-card-pro";
        version = "4.0.0";

        src = pkgs.fetchFromGitHub {
          owner = "alexpfau";
          repo = "calendar-card-pro";
          tag = "v${version}";
          hash = "sha256-ZwCJZHRoyie/WkwsNATD5iDlDqJOIPg35C/gwCOap0I=";
        };

        npmDepsHash = "sha256-+HILd9NxNmMoW6VkDdUW4CGQ4xAUjQ0+V5qMHyafmow=";

        installPhase = ''
          runHook preInstall

          mkdir $out
          cp dist/calendar-card-pro.js dist/editor.js $out/

          runHook postInstall
        '';
      })
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
      # Hand-written, no build step: a single file served straight out of the
      # merged module dir. Ported from a Claude Design document, so there is no
      # upstream to track. Only the renderer lives here — the budget figures it
      # draws are configured on the card in the UI and stay in .storage, out of
      # this public repository.
      # `version` is the ?cache-buster in the generated resource URL — bump it
      # on every edit to the .js or browsers keep serving the old card.
      # The build runs the card's tests, so a failing test blocks the deploy.
      (pkgs.runCommandLocal "budget-sankey-card"
        {
          version = "8";
          nativeBuildInputs = [ pkgs.nodejs ];
          passthru.entrypoint = "budget-sankey-card.js";
        }
        ''
          cp ${./lovelace}/* .
          node --test
          install -Dm444 budget-sankey-card.js $out/budget-sankey-card.js
        ''
      )
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

      # Parallel export to VictoriaMetrics, which speaks the InfluxDB v1 line
      # protocol on its main port. This is the long-term archive; the recorder
      # below keeps only a short window (see purge_keep_days).
      #
      # Filters mirror recorder.exclude — no point paying to store the entities
      # Postgres already refuses.
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
        # Attributes that are constant, huge, or non-numeric. hvac_action is
        # deliberately NOT ignored: it is what binary_sensor.needs_heating keys
        # off, so without it no heating analysis is possible after the fact.
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
          "value"
          "writeable"
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
        # Entity map for the n8n Home Agent, read through /api/states because
        # the agent's non-admin token cannot render templates itself. Trigger
        # based so it holds no state listeners on the entities it lists; the
        # 30-minute refresh picks up new entities and area changes.
        #
        # `controllable` is the allowlist n8n's call_service sub-workflow
        # enforces, so what the agent is shown and what it may touch cannot
        # drift. Entities are denied by the `no_ai` label (managed in the HA
        # UI) or by name for infrastructure: config/diagnostic controls, the
        # network rack and switch, Zigbee pairing, the ONT reset and the
        # heating self-test.
        (
          let
            prelude = ''
              {%- set ctl = ['light', 'switch', 'fan', 'climate', 'cover', 'media_player', 'scene', 'script', 'input_boolean', 'input_number', 'input_select', 'button'] -%}
              {%- set deny_labelled = label_entities('no_ai') -%}
              {%- set deny_re = '(_identify|_child_lock|_power_cycle|_restart|permit_join|network_rack|reset_ont|power_outage_memory|self_test)' -%}
              {%- set ok = namespace(ids=[]) -%}
              {%- for s in states | selectattr('domain', 'in', ctl) -%}
                {%- if s.entity_id not in deny_labelled and not s.entity_id is search(deny_re) -%}
                  {%- set ok.ids = ok.ids + [s.entity_id] -%}
                {%- endif -%}
              {%- endfor -%}
            '';
          in
          {
            trigger = [
              {
                platform = "homeassistant";
                event = "start";
              }
              {
                platform = "event";
                event_type = "event_template_reloaded";
              }
              {
                platform = "time_pattern";
                minutes = "/30";
              }
            ];
            sensor = [
              {
                name = "n8n House Map";
                unique_id = "n8n_house_map";
                icon = "mdi:floor-plan";
                state = "{{ now().isoformat() }}";
                attributes = {
                  controllable = ''
                    ${prelude}
                    {{ ok.ids }}
                  '';
                  # One line per area: controllable entities plus the
                  # temperature, humidity and door/window/motion sensors the
                  # agent needs to answer "is it warm/open" without a search.
                  map = ''
                    ${prelude}
                    {%- set ns = namespace(lines=[], seen=[]) -%}
                    {%- for area in areas() -%}
                      {%- set items = namespace(list=[]) -%}
                      {%- for e in area_entities(area) -%}
                        {%- set d = e.split('.')[0] -%}
                        {%- set dc = state_attr(e, 'device_class') -%}
                        {%- if e in ok.ids
                              or (d == 'sensor' and dc in ['temperature', 'humidity'])
                              or (d == 'binary_sensor' and dc in ['door', 'window', 'opening', 'motion', 'occupancy']) -%}
                          {%- set items.list = items.list + [e ~ ' (' ~ (state_attr(e, 'friendly_name') or e) ~ ')'] -%}
                          {%- set ns.seen = ns.seen + [e] -%}
                        {%- endif -%}
                      {%- endfor -%}
                      {%- if items.list -%}
                        {%- set ns.lines = ns.lines + [area_name(area) ~ ': ' ~ items.list | join(', ')] -%}
                      {%- endif -%}
                    {%- endfor -%}
                    {%- set loose = namespace(list=[]) -%}
                    {%- for e in ok.ids | reject('in', ns.seen) -%}
                      {%- set loose.list = loose.list + [e ~ ' (' ~ (state_attr(e, 'friendly_name') or e) ~ ')'] -%}
                    {%- endfor -%}
                    {%- if loose.list -%}
                      {%- set ns.lines = ns.lines + ['No area: ' ~ loose.list | join(', ')] -%}
                    {%- endif -%}
                    {{ ns.lines | join('\n') }}
                  '';
                };
              }
            ];
          }
        )
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
        # Raw states cost ~60 MB/day in Postgres; a year of them is ~22 GB and
        # nothing in the UI reaches past a few weeks. Long-term statistics live
        # in separate tables and are NEVER purged, so year-scale trends survive
        # regardless of this value. Full-resolution history is kept in
        # VictoriaMetrics instead (see the influxdb block above).
        purge_keep_days = 30;
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

      # YAML http config is deprecated (removed in HA 2027.2.0). The old
      # block (use_x_forwarded_for, trusted_proxies 127.0.0.1, ip_ban_enabled
      # false for fail2ban) was imported into /var/lib/hass/.storage and now
      # lives outside version control; restore it via Settings > System >
      # Network if /var/lib/hass is ever rebuilt from scratch.

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
          # Pinned rather than "auto" so a future default change can't swap the
          # model silently. Parakeet ignores beamSize and initialPrompt.
          sttLibrary = "sherpa";
          model = "sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8";
          extraArgs = [
            # The default is 4 threads, and the module has no option for it.
            "--cpu-threads"
            "16"
            # Trims silence around speech before transcription. It takes any
            # following non-flag words as library names, so keep it last.
            "--vad-clip"
          ];
        };
      };

      piper.servers.ha = {
        enable = true;
        uri = "tcp://0.0.0.0:10200";
        voice = "en_GB-alan-medium";
      };
    };
  };

  # Kokoro-82M TTS over Wyoming, added to HA as a second Wyoming service at
  # 127.0.0.1:10210. Not in nixpkgs. Runs on CPU: the P2000 is Pascal, which
  # current onnxruntime/PyTorch CUDA builds no longer target.
  #
  # Every Docker Hub tag from 1.1.0 on, including :latest, points at the 2.4 GB
  # CUDA build: the release workflow pushes the cpu and cuda variants under the
  # same tag. onnxruntime falls back to the CPU provider without a GPU, so it
  # still works, just larger than the slim CPU image.
  virtualisation.oci-containers.containers.kokoro-wyoming = {
    image = "docker.io/nordwestt/kokoro-wyoming:1.1.0";
    cmd = [
      "--voice"
      "bf_emma"
    ];
    ports = [ "127.0.0.1:10210:10210/tcp" ];
  };

}

{
  pkgs,
  config,
  lib,
  ...
}:
{
  systemd.services.zigbee2mqtt = {
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      EnvironmentFile = [
        config.age.secrets."nexus/zigbee2mqtt.env".path
      ];
      Restart = "on-failure";
      RestartSec = lib.mkForce "60";
    };
    unitConfig = {
      # Retry every RestartSec forever: after an unclean Nexus reboot the
      # coordinator can take minutes to answer, and a start limit would leave
      # the unit in start-limit-hit with no further retries.
      StartLimitIntervalSec = 0;
    };
  };

  services.zigbee2mqtt = {
    enable = true;
    package = pkgs.zigbee2mqtt_2;

    settings = {
      serial = {
        port = "tcp://zigbee-coordinator.iot.internal:6638";
        adapter = "zstack";
        baudrate = 115200;
      };

      frontend = {
        enabled = true;
        port = 8099;
      };

      mqtt = {
        server = "mqtt://localhost:1883";
        base_topic = "zigbee2mqtt";
      };

      advanced = {
        transmit_power = 20;
      };

      # Without this, entities keep serving their last reported value forever,
      # so a stale reading is indistinguishable from a fresh one downstream.
      # Defaults: mains devices marked offline after 10 min, battery after 1500.
      availability = {
        enabled = true;
      };

      homeassistant = {
        enabled = true;
      };
    };

  };
}

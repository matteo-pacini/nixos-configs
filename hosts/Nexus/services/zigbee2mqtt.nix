{
  pkgs,
  config,
  lib,
  ...
}:
{
  systemd.services.zigbee2mqtt = {
    serviceConfig = {
      EnvironmentFile = [
        config.age.secrets."nexus/zigbee2mqtt.env".path
      ];
      Restart = "on-failure";
      RestartSec = lib.mkForce "60";
    };
    unitConfig = {
      StartLimitBurst = 3;
      StartLimitIntervalSec = 300;
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

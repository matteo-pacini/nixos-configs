{ pkgs, config, ... }:
{
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
        channel = 25;
        pan_id = "!${config.age.secrets."nexus/zigbee2mqtt.yaml".path} pan_id";
        ext_pan_id = "!${config.age.secrets."nexus/zigbee2mqtt.yaml".path} ext_pan_id";
        network_key = "!${config.age.secrets."nexus/zigbee2mqtt.yaml".path} network_key";
      };

      homeassistant = {
        enabled = true;
      };
    };

  };
}

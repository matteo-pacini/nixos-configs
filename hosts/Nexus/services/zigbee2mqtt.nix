{ pkgs, ... }:
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
        pan_id = "GENERATE";
        ext_pan_id = "GENERATE";
        network_key = "GENERATE";
      };

      homeassistant = {
        enabled = true;
      };
    };

  };
}

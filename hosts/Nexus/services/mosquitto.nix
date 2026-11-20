{ config, ... }:
{
  services.mosquitto = {
    enable = true;
    persistence = true;
    settings = {
      autosave_interval = 30;
      autosave_on_changes = false;
    };
    listeners = [
      {
        address = "127.0.0.1";
        port = 1883;
        acl = [ "pattern readwrite #" ];
        omitPasswordAuth = true;
        settings.allow_anonymous = true;
      }
      # LAN access without auth (for BrightFalls): its own topics and Zigbee2MQTT.
      # Write access means anything that can reach this listener can command Zigbee devices.
      {
        address = "192.168.10.14";
        port = 1883;
        acl = [
          "pattern readwrite pc/brightfalls/#"
          "pattern readwrite ${config.services.zigbee2mqtt.settings.mqtt.base_topic}/#"
        ];
        omitPasswordAuth = true;
        settings.allow_anonymous = true;
      }
    ];
  };
}

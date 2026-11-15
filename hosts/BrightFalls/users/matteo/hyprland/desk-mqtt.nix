# The office panel's MQTT client, `desk-mqtt` (protocol: desk-mqtt.py).
# `configFile` holds the broker and the Zigbee2MQTT names (README.md,
# "Office: desk-mqtt"); the devices below are only ids, kinds and labels.
{
  writers,
  writeText,
  python3Packages,
  configFile ? "/run/agenix/brightfalls/office-mqtt",
}:
let
  devices = writeText "desk-mqtt-devices.json" (
    builtins.toJSON [
      {
        id = "light";
        kind = "light";
        label = "Light";
      }
      {
        id = "blind";
        kind = "blind";
        label = "Blind";
      }
      {
        id = "pc";
        kind = "socket";
        label = "PC";
      }
      {
        id = "egpu";
        kind = "socket";
        label = "eGPU";
      }
      {
        id = "desk1";
        kind = "socket";
        label = "Desk 1";
      }
      {
        id = "desk2";
        kind = "socket";
        label = "Desk 2";
      }
      {
        id = "desk3";
        kind = "socket";
        label = "Desk 3";
      }
    ]
  );
in
writers.writePython3Bin "desk-mqtt"
  {
    libraries = [ python3Packages.paho-mqtt ];
    flakeIgnore = [ "E501" ];
  }
  (
    builtins.replaceStrings [ "@devices@" "@config@" ] [ "${devices}" configFile ] (
      builtins.readFile ./desk-mqtt.py
    )
  )

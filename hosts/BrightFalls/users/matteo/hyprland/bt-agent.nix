# The Bluetooth panel's pairing agent (user/quickshell/bluetooth/Agent.qml
# starts it once per shell as `desk-bt-agent`). Protocol: bt-agent.py.
{ writers, python3Packages }:
writers.writePython3Bin "desk-bt-agent" {
  libraries = [ python3Packages.dbus-fast ];
  flakeIgnore = [
    "E501"
    # dbus-fast reads D-Bus signatures ("o", "u") from the annotations.
    "F821"
    "F722"
  ];
} (builtins.readFile ./bt-agent.py)

{ pkgs, ... }:
{
  # `fans` sets the baseline, `with-fans` holds a duty for one command. Both run
  # without sudo through the ipmi group (udev rule in services/home-assistant).
  environment.systemPackages = [ (pkgs.callPackage ./package.nix { }) ];

  users.users.matteo.extraGroups = [ "ipmi" ];

  # Pre-created so every ipmi member (matteo, hass) can open and write them
  # regardless of who touches them first.
  systemd.tmpfiles.rules = [
    "d /run/nexus-fans 0770 root ipmi -"
    "f /run/nexus-fans/lock 0660 root ipmi -"
    "f /run/nexus-fans/state 0660 root ipmi -"
    "f /run/nexus-fans/baseline 0660 root ipmi - auto"
    "f /run/nexus-fans/override 0660 root ipmi -"
  ];
}

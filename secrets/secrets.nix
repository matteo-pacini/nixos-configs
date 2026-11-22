# Centralized key management for agenix
#
# Use SSH public keys directly (agenix/age supports them natively)
# Get host key with: cat /etc/ssh/ssh_host_ed25519_key.pub
#
# To re-encrypt all secrets after modifying this file:
#   cd secrets && agenix --rekey -i /path/to/valid/identity

let
  inherit (import ../lib/ssh-mesh.nix) hosts;
  nexus = hosts.Nexus.hostKey;
  worklaptop = hosts.WorkLaptop.hostKey;
  brightfalls = hosts.BrightFalls.hostKey;
  nightsprings = hosts.NightSprings.hostKey;
  cauldronlake = hosts.CauldronLake.hostKey;
in
{
  "nexus/disk0.age".publicKeys = [ nexus ];
  "nexus/disk1.age".publicKeys = [ nexus ];
  "nexus/disk2.age".publicKeys = [ nexus ];
  "nexus/disk3.age".publicKeys = [ nexus ];
  "nexus/disk4.age".publicKeys = [ nexus ];
  "nexus/disk5.age".publicKeys = [ nexus ];
  "nexus/disk6.age".publicKeys = [ nexus ];
  "nexus/disk7.age".publicKeys = [ nexus ];
  "nexus/disk8.age".publicKeys = [ nexus ];
  "nexus/disk9.age".publicKeys = [ nexus ];

  "nexus/attic-env.age".publicKeys = [ nexus ];
  "nexus/attic-netrc.age".publicKeys = [ nexus ];
  # Telegram bot; also used by the comin deploy hook on BrightFalls/NightSprings/CauldronLake.
  "nexus/janitor.env.age".publicKeys = [
    nexus
    brightfalls
    nightsprings
    cauldronlake
  ];
  "nexus/restic-env.age".publicKeys = [ nexus ];
  "nexus/restic-password.age".publicKeys = [ nexus ];
  "nexus/route53-env.age".publicKeys = [ nexus ];
  "nexus/fpnas-sync-key.age".publicKeys = [ nexus ];
  "nexus/grafana-admin-password.age".publicKeys = [ nexus ];
  "nexus/grafana-secret-key.age".publicKeys = [ nexus ];
  "nexus/zigbee2mqtt.env.age".publicKeys = [ nexus ];
  "nexus/n8n-env.age".publicKeys = [ nexus ];
  "nexus/fuel-finder.age".publicKeys = [ nexus ];
  "nexus/fuel-finder-station.age".publicKeys = [ nexus ];
  "nexus/ssh-mesh-ca.age".publicKeys = [ nexus ];

  "worklaptop/attic-netrc.age".publicKeys = [ worklaptop ];

  "brightfalls/attic-netrc.age".publicKeys = [ brightfalls ];
  # CalDAV base URL, user and app password for the read-only calendar sync.
  "brightfalls/caldav-url.age".publicKeys = [ brightfalls ];
  "brightfalls/caldav-user.age".publicKeys = [ brightfalls ];
  "brightfalls/caldav-password.age".publicKeys = [ brightfalls ];
  # MQTT broker and Zigbee2MQTT device names for the office panel's desk-mqtt.
  "brightfalls/office-mqtt.age".publicKeys = [ brightfalls ];
  # Location, warnings region and broker for the weather panel's desk-weather.
  "brightfalls/weather.age".publicKeys = [ brightfalls ];

  "nightsprings/attic-netrc.age".publicKeys = [ nightsprings ];

  "shared/openrouter.env.age".publicKeys = [
    brightfalls
    nexus
    nightsprings
    worklaptop
  ];
}

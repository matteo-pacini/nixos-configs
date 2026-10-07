# Centralized key management for agenix
#
# Use SSH public keys directly (agenix/age supports them natively)
# Get host key with: cat /etc/ssh/ssh_host_ed25519_key.pub
#
# To re-encrypt all secrets after modifying this file:
#   cd secrets && agenix --rekey -i /path/to/valid/identity

let
  # Host SSH public keys (used directly by age for encryption)
  inherit (import ../lib/ssh-mesh.nix) hosts;
  nexus = hosts.Nexus.hostKey;
  worklaptop = hosts.WorkLaptop.hostKey;
  brightfalls = hosts.BrightFalls.hostKey;
  nightsprings = hosts.NightSprings.hostKey;
in
{
  # Nexus disk encryption secrets
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

  # Nexus service secrets
  "nexus/attic-env.age".publicKeys = [ nexus ];
  "nexus/attic-netrc.age".publicKeys = [ nexus ];
  "nexus/janitor.env.age".publicKeys = [ nexus ];
  "nexus/restic-env.age".publicKeys = [ nexus ];
  "nexus/restic-password.age".publicKeys = [ nexus ];
  "nexus/route53-env.age".publicKeys = [ nexus ];
  "nexus/grafana-admin-password.age".publicKeys = [ nexus ];
  "nexus/grafana-secret-key.age".publicKeys = [ nexus ];
  "nexus/zigbee2mqtt.env.age".publicKeys = [ nexus ];
  "nexus/nextcloud-admin-password.age".publicKeys = [ nexus ];
  "nexus/geoip-license-key.age".publicKeys = [ nexus ];
  "nexus/n8n-env.age".publicKeys = [ nexus ];
  "nexus/ssh-mesh-ca.age".publicKeys = [ nexus ];

  # WorkLaptop service secrets
  "worklaptop/attic-netrc.age".publicKeys = [ worklaptop ];

  # BrightFalls service secrets
  "brightfalls/attic-netrc.age".publicKeys = [ brightfalls ];

  # NightSprings service secrets
  "nightsprings/attic-netrc.age".publicKeys = [ nightsprings ];

  # Shared service secrets (decryptable by multiple hosts)
  "shared/openrouter.env.age".publicKeys = [
    brightfalls
    nexus
    nightsprings
    worklaptop
  ];
}

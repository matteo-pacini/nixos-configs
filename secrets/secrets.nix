# Centralized key management for agenix
#
# To get the age public key from an SSH host key:
#   nix-shell -p ssh-to-age --run 'cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age'
#
# To re-encrypt all secrets after modifying this file:
#   cd secrets && agenix --rekey -i /path/to/valid/identity

let
  # Host public keys (from SSH host keys converted to age format)
  # TODO: Replace with actual key from Nexus
  nexus = "age1REPLACE_WITH_NEXUS_KEY";
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
  "nexus/janitor.env.age".publicKeys = [ nexus ];
  "nexus/restic-env.age".publicKeys = [ nexus ];
  "nexus/restic-password.age".publicKeys = [ nexus ];
  "nexus/wireguard.env.age".publicKeys = [ nexus ];
  "nexus/route53-env.age".publicKeys = [ nexus ];
  "nexus/zigbee2mqtt.env.age".publicKeys = [ nexus ];
  "nexus/grafana-admin-password.age".publicKeys = [ nexus ];
  "nexus/geoip-license-key.age".publicKeys = [ nexus ];
  "nexus/backblaze-b2.env.age".publicKeys = [ nexus ];
}

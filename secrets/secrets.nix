# Centralized key management for agenix
#
# Use SSH public keys directly (agenix/age supports them natively)
# Get host key with: cat /etc/ssh/ssh_host_ed25519_key.pub
#
# To re-encrypt all secrets after modifying this file:
#   cd secrets && agenix --rekey -i /path/to/valid/identity

let
  # Host SSH public keys (used directly by age for encryption)
  nexus = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICqoR66tb+LELPbehy1TJp0Y8hHVYPEgtg1WUDMILe/n";
  worklaptop = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPtM6cXF6v03BIDdYeMYUHuuoLljzT2Lx+judeJSag8c";
  brightfalls = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFhrAwaSAjKS/FLYRZRNkgpRn8gZECa+Sc0t32gENbv1";
in
{
  # Nexus disk encryption secrets
  "nexus/disk0.age".publicKeys = [ nexus ];
  # disk1 drained 2026-05-27 — see hosts/Nexus/hardware-extra.nix
  # "nexus/disk1.age".publicKeys = [ nexus ];
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
  "nexus/zigbee2mqtt.env.age".publicKeys = [ nexus ];
  "nexus/nextcloud-admin-password.age".publicKeys = [ nexus ];
  "nexus/geoip-license-key.age".publicKeys = [ nexus ];
  "nexus/backblaze-b2.env.age".publicKeys = [ nexus ];

  # WorkLaptop service secrets
  "worklaptop/attic-netrc.age".publicKeys = [ worklaptop ];

  # BrightFalls service secrets
  "brightfalls/attic-netrc.age".publicKeys = [ brightfalls ];
}

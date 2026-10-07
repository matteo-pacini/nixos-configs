# nix.buildMachines entry for Nexus as a remote builder, reached over the
# SSH mesh. The connection is made by nix-daemon (root), which reads the
# user's mesh key; ssh loads the adjacent mesh-cert.pub automatically.
# publicHostKey is left unset: the ssh-mesh modules pin Nexus's host key in
# the system known_hosts, which root's ssh reads.
#
# Shared by the NixOS and Darwin nix-core modules.
{ sshKey }:
let
  nexus = (import ../../lib/ssh-mesh.nix).hosts.Nexus;
in
{
  protocol = "ssh-ng";
  hostName = "${nexus.lan}:${toString nexus.port}";
  sshUser = nexus.user;
  inherit sshKey;
  # aarch64-linux runs under binfmt emulation (Nexus extraPlatforms).
  systems = [
    "x86_64-linux"
    "aarch64-linux"
  ];
  # Each job gets Nexus's own `cores` (8), so 8 jobs use 64 of its 72
  # threads and leave ~15 GiB RAM per job, with headroom for its services.
  maxJobs = 8;
  speedFactor = 100;
  supportedFeatures = [
    "big-parallel"
    "benchmark"
  ];
}

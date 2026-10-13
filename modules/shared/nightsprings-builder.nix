# nix.buildMachines entry for NightSprings (M1 Max) as an aarch64-darwin
# remote builder, reached over the SSH mesh via Tailscale. As with
# nexus-builder.nix, nix-daemon (root) reads the user's mesh key and the
# ssh-mesh modules pin NightSprings's host key in the system known_hosts.
#
# Used by the NixOS nix-core module.
{ sshKey }:
let
  nightsprings = (import ../../lib/ssh-mesh.nix).hosts.NightSprings;
in
{
  protocol = "ssh-ng";
  hostName = "${nightsprings.tailscale}:${toString nightsprings.port}";
  sshUser = nightsprings.user;
  inherit sshKey;
  systems = [ "aarch64-darwin" ];
  # NightSprings runs with cores = 0 (each job may use all 10 cores), so a
  # few concurrent jobs already saturate it; it is also a laptop in daily use.
  maxJobs = 4;
  speedFactor = 50;
  # Its own system-features, minus nixos-test (no aarch64-darwin derivation
  # needs it).
  supportedFeatures = [
    "apple-virt"
    "benchmark"
    "big-parallel"
  ];
}

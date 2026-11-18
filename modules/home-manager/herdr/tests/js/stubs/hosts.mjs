// Stand-in for lib/hosts.js, which workbench.nix generates per machine and so
// isn't in the repo. Shaped like BrightFalls's copy.

export const SELF = "brightfalls";
export const HOSTS = {
  brightfalls: { label: "BrightFalls", device: "desktop", os: "NixOS" },
  nexus: { label: "Nexus", device: "server", os: "NixOS" },
};

# SSH mesh: which host may SSH into which, enforced by an OpenSSH user CA.
#
# Pure data, imported by modules/{nixos,darwin}/ssh-mesh.nix,
# modules/home-manager/ssh.nix, hosts/Nexus/services/ssh-ca.nix,
# lib/ssh-mesh-krl.nix and secrets/secrets.nix (host keys).
# See docs/ssh-mesh-handbook.md.
{
  # Public half of secrets/nexus/ssh-mesh-ca.age.
  caPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDUOaL0BoxEKXPezthYmsM/MvWQZ/oFYwKD5rirTHmsR ssh-mesh-ca";

  # The host running the signer (sshca user). Clients renew against it.
  signer = "Nexus";

  # principal: cert principal for logins into this host, and the cert key ID
  #   (source identity) when this host is the client.
  # user: account mesh logins land in. lan/tailscale/port: only on hosts that
  #   run sshd. hostKey: /etc/ssh/ssh_host_ed25519_key.pub, also the agenix
  #   recipient for this host. lanOnly: this host has no Tailscale, so its
  #   outbound mesh connections use lan; every other source uses tailscale.
  #   A destination without tailscale is reached over lan only.
  hosts = {
    Nexus = {
      principal = "nexus";
      user = "matteo";
      lan = "nexus.home.internal";
      tailscale = "nexus-ts.walrus-draconis.ts.net";
      port = 1788;
      hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICqoR66tb+LELPbehy1TJp0Y8hHVYPEgtg1WUDMILe/n";
    };
    BrightFalls = {
      principal = "brightfalls";
      user = "matteo";
      lan = "brightfalls.home.internal";
      tailscale = "brightfalls-ts.walrus-draconis.ts.net";
      port = 1788;
      hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFhrAwaSAjKS/FLYRZRNkgpRn8gZECa+Sc0t32gENbv1";
    };
    CauldronLake = {
      principal = "cauldronlake";
      user = "matteo";
      lan = "cauldronlake.home.internal";
      tailscale = "cauldronlake-ts.walrus-draconis.ts.net";
      port = 1788;
      hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINkgSpyZfE5qloOO4wZRqdzle40Z/f09qWjIZklJ0ftm";
    };
    NightSprings = {
      principal = "nightsprings";
      user = "matteo";
      lan = "nightsprings.home.internal";
      tailscale = "nightsprings-ts.walrus-draconis.ts.net";
      # macOS sshd is socket-activated by launchd on 22; sshd_config Port is ignored.
      port = 22;
      hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPN4uiOzzFtelR6mzxIqRKG8PArHchOqL0U844UZSet4";
    };
    # Source only, no sshd: the work MDM (Kandji) turns Remote Login back off
    # every ~15 minutes.
    WorkLaptop = {
      principal = "worklaptop";
      lanOnly = true;
      hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPtM6cXF6v03BIDdYeMYUHuuoLljzT2Lx+judeJSag8c";
    };
  };

  # source -> destinations it may log into.
  allow = {
    Nexus = [
      "BrightFalls"
      "NightSprings"
      "CauldronLake"
    ];
    BrightFalls = [
      "Nexus"
      "NightSprings"
      "CauldronLake"
    ];
    NightSprings = [
      "Nexus"
      "BrightFalls"
      "CauldronLake"
    ];
    CauldronLake = [
      "Nexus"
      "BrightFalls"
      "NightSprings"
    ];
    WorkLaptop = [
      "Nexus"
      "BrightFalls"
      "NightSprings"
      "CauldronLake"
    ];
  };

  # Cert key IDs (principals above) that every destination refuses, even
  # before their certs expire. Revokes all certs ever issued under that ID,
  # so remove the entry before re-adding a host with the same principal.
  revokedKeyIds = [ ];
}

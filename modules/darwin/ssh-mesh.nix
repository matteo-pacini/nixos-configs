{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.sshMesh;
  mesh = import ../../lib/ssh-mesh.nix;
  self = mesh.hosts.${cfg.host};
  isDestination = lib.any (src: lib.elem cfg.host mesh.allow.${src}) (lib.attrNames mesh.allow);
in
{
  options.custom.sshMesh = {
    enable = lib.mkEnableOption "SSH mesh (user CA trust and pinned mesh host keys)";
    host = lib.mkOption {
      type = lib.types.enum (lib.attrNames mesh.hosts);
      description = "This host's name in lib/ssh-mesh.nix.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        programs.ssh.knownHosts = lib.mapAttrs (_: h: {
          # known_hosts writes port 22 as a bare name and others as [name]:port.
          hostNames = map (n: if h.port == 22 then n else "[${n}]:${toString h.port}") [
            h.lan
            h.tailscale
          ];
          publicKey = h.hostKey;
        }) (lib.filterAttrs (_: h: h ? lan) mesh.hosts);
      }
      (lib.mkIf isDestination {
        services.openssh.enable = true;
        environment.etc."ssh/authorized_principals.d/${self.user}".text = self.principal + "\n";
        # Apple's sshd allows password login by default; mesh logins are cert-only.
        services.openssh.extraConfig = ''
          TrustedUserCAKeys ${pkgs.writeText "ssh-mesh-ca.pub" mesh.caPublicKey}
          AuthorizedPrincipalsFile /etc/ssh/authorized_principals.d/%u
          PasswordAuthentication no
          KbdInteractiveAuthentication no
        '';
      })
    ]
  );
}

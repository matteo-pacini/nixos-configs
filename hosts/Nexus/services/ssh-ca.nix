{ config, pkgs, ... }:
let
  mesh = import ../../../lib/ssh-mesh.nix;
  signer = pkgs.callPackage ../../../packages/ssh-mesh-sign.nix {
    caKey = config.age.secrets."nexus/ssh-mesh-ca".path;
    inherit (mesh) caPublicKey;
    # Keyed by cert key ID, which is the source host's principal.
    principals = builtins.listToAttrs (
      map (src: {
        name = mesh.hosts.${src}.principal;
        value = map (dest: mesh.hosts.${dest}.principal) mesh.allow.${src} ++ [ "renew" ];
      }) (builtins.attrNames mesh.allow)
    );
  };
in
{
  # Mesh hosts renew their user certificate by logging in here with the
  # current one (principal "renew") and piping a new public key in.
  users.users.sshca = {
    isSystemUser = true;
    group = "sshca";
    # ForceCommand runs through the login shell, so nologin would block it.
    shell = pkgs.bashInteractive;
    openssh.authorizedPrincipals = [ "renew" ];
  };
  users.groups.sshca = { };

  # Bootstrap path: sudo -u sshca ssh-mesh-sign --host <principal>
  environment.systemPackages = [ signer ];

  services.openssh.extraConfig = ''
    Match User sshca
      AuthorizedKeysFile none
      ForceCommand ${pkgs.lib.getExe signer}
      ExposeAuthInfo yes
      PermitTTY no
      PermitUserRC no
      AllowAgentForwarding no
      AllowTcpForwarding no
      AllowStreamLocalForwarding no
      X11Forwarding no
  '';
}

# OpenSSH key revocation list for the mesh CA, built from
# revokedKeyIds in lib/ssh-mesh.nix. Used as sshd's RevokedKeys; an empty
# list yields a valid empty KRL, so the setting never needs to be toggled.
{ runCommand, openssh }:
let
  mesh = import ./ssh-mesh.nix;
in
runCommand "ssh-mesh-revoked.krl"
  {
    nativeBuildInputs = [ openssh ];
    caPublicKey = mesh.caPublicKey;
    spec = builtins.concatStringsSep "" (map (id: "id: ${id}\n") mesh.revokedKeyIds);
    passAsFile = [
      "caPublicKey"
      "spec"
    ];
  }
  ''
    ssh-keygen -k -f "$out" -s "$caPublicKeyPath" "$specPath"
  ''

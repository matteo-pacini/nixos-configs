{
  writeShellApplication,
  writeText,
  coreutils,
  gnugrep,
  gnused,
  jq,
  openssh,
  util-linux,
  # Path to the CA private key, readable by the signing user.
  caKey,
  caPublicKey,
  # Attrset: source key ID -> list of cert principals.
  principals,
}:

writeShellApplication {
  name = "ssh-mesh-sign";
  runtimeInputs = [
    coreutils
    gnugrep
    gnused
    jq
    openssh
    util-linux
  ];
  runtimeEnv = {
    MESH_CA_KEY = caKey;
    MESH_CA_PUB = writeText "ssh-mesh-ca.pub" caPublicKey;
    MESH_PRINCIPALS = writeText "ssh-mesh-principals.json" (builtins.toJSON principals);
  };
  text = builtins.readFile ./ssh-mesh-sign.sh;
  meta.description = "Sign SSH mesh user certificates (ForceCommand for the sshca user)";
}

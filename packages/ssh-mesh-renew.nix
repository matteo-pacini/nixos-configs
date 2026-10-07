{
  writeShellApplication,
  coreutils,
  gnugrep,
  gnused,
  openssh,
}:

writeShellApplication {
  name = "ssh-mesh-renew";
  # coreutils pinned so `date -d` is GNU date on darwin too.
  runtimeInputs = [
    coreutils
    gnugrep
    gnused
    openssh
  ];
  text = builtins.readFile ./ssh-mesh-renew.sh;
  meta.description = "Rotate this host's SSH mesh key and renew its user certificate";
}

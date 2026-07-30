{
  writeShellApplication,
  coreutils,
  gh,
  git,
  gnugrep,
  gnused,
  openssh,
}:

writeShellApplication {
  name = "rotate-github-key";
  # sudo and nixos-rebuild/darwin-rebuild are intentionally taken from the
  # user's PATH, not pinned here.
  runtimeInputs = [
    coreutils
    gh
    git
    gnugrep
    gnused
    openssh
  ];
  text = builtins.readFile ./rotate-github-key.sh;
  meta.description = "Rotate this host's GitHub SSH key (auth + signing) and update nixos-configs";
}

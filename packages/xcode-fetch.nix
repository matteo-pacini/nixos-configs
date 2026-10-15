{
  writeShellApplication,
  coreutils,
  git,
  jq,
  xcodes,
}:

writeShellApplication {
  name = "xcode-fetch";
  # nix, sudo and attic-push-closure are intentionally taken from the user's
  # PATH: the push needs the host's system-installed attic token wrapper.
  runtimeInputs = [
    coreutils
    git
    jq
    xcodes
  ];
  text = builtins.readFile ./xcode-fetch.sh;
  meta.description = "Download an Xcode .xip, push it to attic and record its hash for custom.xcode";
}

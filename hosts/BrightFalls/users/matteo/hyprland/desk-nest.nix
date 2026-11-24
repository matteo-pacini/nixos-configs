# desk-nest (README.md, "desk-nest"): the shell in a sealed nested Hyprland,
# run from a checkout. Every program it runs, outside the sandbox and in it,
# comes from here.
{
  lib,
  writeShellApplication,
  writeShellScript,
  runCommand,
  bash,
  bubblewrap,
  coreutils,
  dbus,
  diffutils,
  findutils,
  gawk,
  git,
  glib,
  gnugrep,
  gnused,
  grim,
  hyprland,
  inotify-tools,
  iproute2,
  linux-pam,
  python3,
  quickshell,
  rsync,
  systemd,
  util-linux,
  wl-clipboard,
}:
let
  # The lock's stand-in PAM service directory (nest/pam).
  pam = runCommand "desk-nest-pam" { } ''
    mkdir $out
    substitute ${./nest/pam/desk-lock} $out/desk-lock \
      --replace-fail @pam_exec@ ${linux-pam}/lib/security/pam_exec.so \
      --replace-fail @pam_deny@ ${linux-pam}/lib/security/pam_deny.so \
      --replace-fail @check@ ${writeShellScript "nest-unlock-check" (builtins.readFile ./nest/pam/check.sh)}
  '';

  # Inside the sandbox, after the checkout's nest/fakes/bin. Nothing from the
  # user's PATH: a command the shell runs that is neither faked nor here is
  # not found, rather than the real one.
  innerPath = lib.makeBinPath [
    bash
    coreutils
    dbus
    findutils
    gawk
    glib.bin
    gnugrep
    gnused
    grim
    hyprland
    iproute2
    python3
    quickshell
    wl-clipboard
  ];
in
writeShellApplication {
  name = "desk-nest";
  runtimeInputs = [
    bubblewrap
    coreutils
    dbus
    diffutils
    findutils
    gawk
    git
    gnugrep
    gnused
    hyprland
    inotify-tools
    python3
    rsync
    systemd
    util-linux
  ];
  text = ''
    hyprland="${lib.getExe' hyprland "Hyprland"}"
    qs="${lib.getExe' quickshell "qs"}"
    nest_lua="${./nest/hypr/nest.lua}"
    nest_pam="${pam}"
    inner_path="${innerPath}"
  ''
  + builtins.readFile ./desk-nest.sh;
}

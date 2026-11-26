# desk-nest (README.md, "desk-nest"): the shell in a sealed nested Hyprland,
# run from a checkout. Every program it runs, outside the sandbox and in it,
# comes from here.
{
  lib,
  adwaita-icon-theme,
  hicolor-icon-theme,
  writeShellApplication,
  writeShellScript,
  runCommand,
  bash,
  bubblewrap,
  coreutils,
  dbus,
  diffutils,
  ffmpeg,
  findutils,
  fira-sans,
  gawk,
  git,
  glib,
  glibc,
  gnugrep,
  gnused,
  grim,
  hyprland,
  hyprpaper,
  inotify-tools,
  iproute2,
  libfaketime,
  linux-pam,
  patchelf,
  pipewire,
  python3,
  quickshell,
  rsync,
  systemd,
  util-linux,
  wf-recorder,
  wireplumber,
  wl-clipboard,
  wlrctl,
  wtype,
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

  # LD_PRELOAD for a program on a --demo nest's frozen clock. glibc's
  # libc_malloc_debug must be the glibc qs runs on; the build fails if
  # quickshell's loader is another one.
  faketimePreload =
    runCommand "desk-nest-faketime-preload" { nativeBuildInputs = [ patchelf ]; }
      ''
        interp=$(patchelf --print-interpreter ${quickshell}/bin/.quickshell-wrapped)
        if [ "''${interp%/lib/*}" != "${glibc}" ]; then
          echo "quickshell runs on $interp, not on ${glibc}" >&2
          exit 1
        fi
        printf '%s' "${glibc}/lib/libc_malloc_debug.so.0 ${libfaketime}/lib/libfaketime.so.1" >$out
      '';

  # desk-nest record's last step (nest/record/caption.sh).
  caption = writeShellApplication {
    name = "desk-nest-caption";
    runtimeInputs = [
      coreutils
      ffmpeg
      (python3.withPackages (p: [ p.pillow ]))
    ];
    text = ''
      captions_py="${./nest/record/captions.py}"
      fonts="${fira-sans}/share/fonts/truetype"
    ''
    + builtins.readFile ./nest/record/caption.sh;
  };

  # Inside the sandbox, after the checkout's nest/fakes/bin and
  # nest/services/bin. Nothing from the user's PATH: a command the shell
  # runs that is neither faked nor here is not found, rather than the real
  # one.
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
    hyprpaper
    pipewire
    iproute2
    # The fakes need only the standard library; the demo's BlueZ stand-in
    # is python-dbusmock (nest/services).
    (python3.withPackages (p: [
      p.python-dbusmock
      p.pygobject3
    ]))
    quickshell
    wf-recorder
    wireplumber
    wl-clipboard
    wlrctl
    wtype
  ];
in
writeShellApplication {
  name = "desk-nest";
  runtimeInputs = [
    bubblewrap
    caption
    ffmpeg
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
    icon_dirs="${adwaita-icon-theme}/share:${hicolor-icon-theme}/share"
    faketime_preload="$(<${faketimePreload})"
    steps_py="${./nest/record/steps.py}"
  ''
  + builtins.readFile ./desk-nest.sh;
}

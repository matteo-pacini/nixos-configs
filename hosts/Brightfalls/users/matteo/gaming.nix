{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  # Raw SLSsteam .so payload (i686): SLSsteam.so + library-inject.so.
  slsSteam = inputs.sls-steam.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # Shared env for the isolated Steam instance. Steam itself ignores XDG_* and
  # derives all state from HOME (so HOME is the real isolation boundary), but the
  # tooling around it — protonup-qt — reads XDG_*, so both are set to keep every
  # tool pointed at the same private tree. Keep it under the real $HOME: a host dir
  # bound into Steam's FHS sandbox, never /tmp or /etc (tmpfs inside it).
  slsHomeSetup = ''
    sls_home="$HOME/.local/share/steam-sls"
    export HOME="$sls_home"
    export XDG_DATA_HOME="$sls_home/.local/share"
    export XDG_CONFIG_HOME="$sls_home/.config"
    export XDG_CACHE_HOME="$sls_home/.cache"
    export XDG_STATE_HOME="$sls_home/.local/state"
    mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME"
  '';

  # Launch Steam with the SLSsteam mod (LD_AUDIT) in the isolated instance. The mod
  # self-strips LD_AUDIT for child procs and self-appends LD_LIBRARY_PATH, so
  # nothing else to set. Do NOT enable SafeMode: NixOS's steamclient.so hash is
  # never in upstream's known-good list, so SafeMode would make the mod disable
  # itself on every launch.
  steam-sls = pkgs.writeShellApplication {
    name = "steam-sls";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      real_home="$HOME"
      ${slsHomeSetup}
      # Reuse the real home's MangoHud config; the isolated HOME has none.
      export MANGOHUD_CONFIGFILE="$real_home/.config/MangoHud/MangoHud.conf"
      export LD_AUDIT="${slsSteam}/library-inject.so:${slsSteam}/SLSsteam.so"

      # System-profile FHS steam (the DRI_PRIME/gamescope-overridden one).
      exec /run/current-system/sw/bin/steam "$@"
    '';
  };

  # protonup-qt pointed at the isolated Steam instead of the normal one. It derives
  # every Steam root from $HOME, so the shared env redirects it; its own config.ini
  # follows XDG_CONFIG_HOME, so it keeps separate settings too. Note: protonup-qt
  # only lists the isolated Steam once it has been run at least once (it validates
  # <root>/config/config.vdf + libraryfolders.vdf) — launch steam-sls first.
  protonup-qt-sls = pkgs.writeShellApplication {
    name = "protonup-qt-sls";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      ${slsHomeSetup}
      exec ${pkgs.protonup-qt}/bin/protonup-qt "$@"
    '';
  };
in
{
  home.file."scripts/steam_disable_http2.sh" = lib.mkIf (pkgs.stdenv.hostPlatform.isx86_64) {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      echo "@nClientDownloadEnableHTTP2PlatformLinux 0" > \
      ~/.steam/steam/steam_dev.cfg
    '';
  };

  home.file.".config/MangoHud/MangoHud.conf".source = ./MangoHud.conf;

  home.packages = [
    (pkgs.retroarch.withCores (cores: with cores; [ beetle-psx-hw ]))
    steam-sls
    pkgs.protonup-qt
    protonup-qt-sls
  ];

  programs.obs-studio = {
    enable = true;
    package = pkgs.obs-studio;
    plugins = with pkgs.obs-studio-plugins; [
      obs-vaapi
      obs-vkcapture
    ];
  };
}

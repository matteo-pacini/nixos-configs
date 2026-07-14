{ pkgs, lib, ... }:
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
    pkgs.protonup-qt
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

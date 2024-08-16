{ pkgs, ... }:
{
  imports = [

    ./git.nix
    ./zsh.nix
  ];

  home.username = "matteo";
  home.homeDirectory = "/home/matteo";

  home.packages = with pkgs; [
    nix-output-monitor
    (
      (ffmpeg_7-full.override ({
        withHeadlessDeps = true;
        withNvcodec = true;
      })).overrideAttrs
      (oldAttrs: {
        NIX_CFLAGS_COMPILE = (oldAttrs.NIX_CFLAGS_COMPILE or "") + " -march=native -O2 -pipe";
      })
    )
  ];

  home.stateVersion = "23.11";

  programs.home-manager.enable = true;
}

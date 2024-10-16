{ pkgs, ... }:

let
  nativeJellyfinFfmpeg =
    (pkgs.jellyfin-ffmpeg.override {
      ffmpeg_6-full = pkgs.ffmpeg_6-full.override ({
        withHeadlessDeps = true;
        withNvcodec = true;
      });
    }).overrideAttrs
      (oldAttrs: {
        NIX_CFLAGS_COMPILE = (oldAttrs.NIX_CFLAGS_COMPILE or "") + " -march=native -O2 -pipe";
      });
  jellyfin = pkgs.jellyfin.override ({ jellyfin-ffmpeg = nativeJellyfinFfmpeg; });
in
{
  users.users."jellyfin" = {
    extraGroups = [ "media" ];
  };

  services.jellyfin = {
    enable = true;
    package = jellyfin;
    group = "media";
  };
}

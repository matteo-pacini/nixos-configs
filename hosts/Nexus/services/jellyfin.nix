{ pkgs, ... }:
let
  overriddenJellyfinFfmpeg = (
    pkgs.jellyfin-ffmpeg.override {
      ffmpeg_7-full = pkgs.ffmpeg_7-full.override ({
        withHeadlessDeps = true;
        withNvcodec = true;
      });
    }
  );
  jellyfin = pkgs.jellyfin.override ({ jellyfin-ffmpeg = overriddenJellyfinFfmpeg; });
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

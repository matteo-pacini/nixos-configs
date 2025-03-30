(
  self: super:
  let
    optimizedForNexus =
      pkg:
      pkg.overrideAttrs (oldAttrs: {
        env = (oldAttrs.env or { }) // {
          NIX_CFLAGS_COMPILE =
            (oldAttrs.env.NIX_CFLAGS_COMPILE or "")
            + " -O2 -ftree-vectorize -march=sandybridge -mtune=sandybridge";
          NIX_CXXFLAGS_COMPILE =
            (oldAttrs.env.NIX_CFLAGS_COMPILE or "")
            + " -O2 -ftree-vectorize -march=sandybridge -mtune=sandybridge";
        };
      });
  in
  {
    jellyfin = super.jellyfin.override ({
      jellyfin-ffmpeg = optimizedForNexus (
        super.jellyfin-ffmpeg.override ({
          ffmpeg_7-full = super.ffmpeg_7-full.override ({
            withHeadlessDeps = true;
            withNvcodec = true;
          });
        })
      );
    });
    mergerfs = optimizedForNexus super.mergerfs;
    snapraid = optimizedForNexus super.snapraid;
  }
)

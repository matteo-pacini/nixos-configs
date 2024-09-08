(
  self: super:
  let
    optimizedForNexus =
      pkg:
      pkg.overrideAttrs (oldAttrs: {
        env = (oldAttrs.env or { }) // {
          NIX_CFLAGS_COMPILE =
            (oldAttrs.env.NIX_CFLAGS_COMPILE or "") + " -O2 -march=sandybridge -mtune=sandybridge";
          NIX_CXXFLAGS_COMPILE =
            (oldAttrs.env.NIX_CFLAGS_COMPILE or "") + " -O2 -march=sandybridge -mtune=sandybridge";
        };
      });
  in
  {

  }
)

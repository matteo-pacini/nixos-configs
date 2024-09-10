(
  self: super:
  let
    optimizedForCauldronLake =
      pkg:
      pkg.overrideAttrs (oldAttrs: {
        env = (oldAttrs.env or { }) // {
          NIX_CFLAGS_COMPILE = (oldAttrs.env.NIX_CFLAGS_COMPILE or "") + " -O2 -march=znver2 -mtune=znver2";
          NIX_CXXFLAGS_COMPILE = (oldAttrs.env.NIX_CFLAGS_COMPILE or "") + " -O2 -march=znver2 -mtune=znver2";
        };
      });
  in
  {

  }
)

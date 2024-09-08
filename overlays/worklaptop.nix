(
  self: super:
  let
    optimizedForWorkLaptop =
      pkg:
      pkg.overrideAttrs (oldAttrs: {
        env = (oldAttrs.env or { }) // {
          NIX_CFLAGS_COMPILE = (oldAttrs.env.NIX_CFLAGS_COMPILE or "") + " -O2 -mcpu=apple-m1";
          NIX_CXXFLAGS_COMPILE = (oldAttrs.env.NIX_CFLAGS_COMPILE or "") + " -O2 -mcpu=apple-m1";
        };
      });
  in
  {

  }
)

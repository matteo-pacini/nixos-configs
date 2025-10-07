(
  self: super:
  let
    optimizedForNightSprings =
      pkg:
      pkg.overrideAttrs (oldAttrs: {
        env = (oldAttrs.env or { }) // {
          NIX_CFLAGS_COMPILE = (oldAttrs.env.NIX_CFLAGS_COMPILE or "") + " -O2 -mcpu=apple-m1";
          NIX_CXXFLAGS_COMPILE = (oldAttrs.env.NIX_CFLAGS_COMPILE or "") + " -O2 -mcpu=apple-m1";
        };
      });
  in
  {
    gtk3 = super.gtk3.overrideAttrs (oldAttrs: {
      patches = (oldAttrs.patches or [ ]) ++ [ ./patches/gtk3-sincos-fix.patch ];
    });
  }
)

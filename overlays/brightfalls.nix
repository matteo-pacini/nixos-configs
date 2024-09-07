(
  self: super:
  let
    optimizedForBrightFalls =
      pkg:
      pkg.overrideAttrs (oldAttrs: {
        env = (oldAttrs.env or { }) // {
          NIX_CFLAGS_COMPILE =
            (oldAttrs.env.NIX_CFLAGS_COMPILE or "") + " -O2 -pipe -march=znver2 -mtune=znver2";
          NIX_CXXFLAGS_COMPILE =
            (oldAttrs.env.NIX_CFLAGS_COMPILE or "") + " -O2 -pipe -march=znver2 -mtune=znver2";
        };
      });
  in
  {
    reshade-steam-proton = super.callPackage ../packages/reshade-steam-proton.nix { };

    qemu = optimizedForBrightFalls super.qemu;
    mangohud = optimizedForBrightFalls super.mangohud;
    mesa = optimizedForBrightFalls super.mesa;

  }
)

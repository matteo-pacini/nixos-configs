(
  self: super:
  let
    optimizedForBrightFalls =
      pkg:
      pkg.overrideAttrs (oldAttrs: {
        env = (oldAttrs.env or { }) // {
          NIX_CFLAGS_COMPILE = (oldAttrs.env.NIX_CFLAGS_COMPILE or "") + " -O2 -march=znver2 -mtune=znver2";
          NIX_CXXFLAGS_COMPILE = (oldAttrs.env.NIX_CFLAGS_COMPILE or "") + " -O2 -march=znver2 -mtune=znver2";
        };
      });
  in
  {
    reshade-steam-proton = super.callPackage ../packages/reshade-steam-proton.nix { };

    mesa = optimizedForBrightFalls super.mesa;
    mangohud = optimizedForBrightFalls super.mangohud;

    qemu = optimizedForBrightFalls (
      super.qemu.override ({
        hostCpuTargets = [
          "i386-softmmu"
          "x86_64-softmmu"
          "aarch64-softmmu"
        ];
      })
    );

  }
)

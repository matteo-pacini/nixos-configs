{ isVM, ... }:
(
  self: super:
  let
    optimizedForBrightFalls =
      pkg:
      if !isVM then
        pkg.overrideAttrs (oldAttrs: {
          env = (oldAttrs.env or { }) // {
            NIX_CFLAGS_COMPILE = (oldAttrs.env.NIX_CFLAGS_COMPILE or "") + " -O2 -march=znver2 -mtune=znver2";
            NIX_CXXFLAGS_COMPILE = (oldAttrs.env.NIX_CFLAGS_COMPILE or "") + " -O2 -march=znver2 -mtune=znver2";
          };
        })
      else
        pkg;
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

    brlaser = super.brlaser.overrideAttrs (oldAttrs: {
      cmakeFlags = (oldAttrs.cmakeFlags or [ ]) ++ [
        "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
      ];
    });

  }
)

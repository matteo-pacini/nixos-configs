{ isVM, ... }:
(
  self: super:
  let
    optimizedForBrightFalls =
      pkg:
      if !isVM then
        pkg.overrideAttrs (oldAttrs: {
          env = (oldAttrs.env or { }) // {
            NIX_CFLAGS_COMPILE = (oldAttrs.env.NIX_CFLAGS_COMPILE or "") + " -O2 -march=znver4 -mtune=znver4";
            NIX_CXXFLAGS_COMPILE = (oldAttrs.env.NIX_CFLAGS_COMPILE or "") + " -O2 -march=znver4 -mtune=znver4";
          };
        })
      else
        pkg;
  in
  {
    reshade-steam-proton = super.callPackage ../packages/reshade-steam-proton.nix { };

    # NOTE: mesa cannot be optimized with -march=znver4 because mesa_clc
    # (a build-time tool) would be compiled with Zen4 instructions and fail
    # to run on build machines that don't support them (SIGILL).
    # Mesa's performance-critical paths are in GPU shaders anyway.
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

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

    qemu = optimizedForBrightFalls (
      super.qemu.override ({
        hostCpuTargets = [
          "i386-softmmu"
          "x86_64-softmmu"
          "aarch64-softmmu"
        ];
      })
    );

    # OVMF/OVMFFull run QEMU during build to generate UEFI vars.
    # Use vanilla QEMU to avoid znver4 instructions failing in TCG emulation.
    # See: https://github.com/NixOS/nixpkgs/issues/381223
    OVMF = super.OVMF.override { qemu = super.qemu; };
    OVMFFull = super.OVMFFull.override { qemu = super.qemu; };

  }
)

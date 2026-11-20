self: super:
let
  optimizedForBrightFalls =
    pkg:
    pkg.overrideAttrs (oldAttrs: {
      env = (oldAttrs.env or { }) // {
        NIX_CFLAGS_COMPILE = (oldAttrs.env.NIX_CFLAGS_COMPILE or "") + " -O2 -march=znver4 -mtune=znver4";
        NIX_CXXFLAGS_COMPILE = (oldAttrs.env.NIX_CFLAGS_COMPILE or "") + " -O2 -march=znver4 -mtune=znver4";
      };
    });
in
{
  reshade-linux = super.callPackage ../packages/reshade-linux { };
  exiled-exchange-2 = super.callPackage ../packages/exiled-exchange-2.nix { };
  path-of-building-poe2 = super.callPackage ../packages/path-of-building-poe2.nix { };
  linuwux-runtime = super.callPackage ../packages/linuwux-runtime.nix { };
  plymouth-brightfalls = super.callPackage ../packages/plymouth-brightfalls { };
  legion-kvm = super.callPackage ../packages/legion-kvm {
    # The guest build boots a VM with buildPackages.qemu_kvm, which derives
    # from the znver4 QEMU below and would not run on the Nexus builder.
    vmTools = super.vmTools.override {
      buildPackages = super.buildPackages // {
        qemu_kvm = super.qemu.override { hostCpuOnly = true; };
      };
    };
  };

  qemu = optimizedForBrightFalls (
    super.qemu.override ({
      hostCpuTargets = [
        "i386-softmmu"
        "x86_64-softmmu"
        "aarch64-softmmu"
      ];
    })
  );

  # OVMF runs QEMU during build to generate UEFI vars. Vanilla QEMU
  # keeps them identical to the cached builds, and a znver4 QEMU could not run
  # on builders without those CPU features. OVMFFull is an override of OVMF,
  # so it inherits this.
  OVMF = super.OVMF.override { qemu = super.qemu; };

  # binfmt's interpreter. nixpkgs derives it from `qemu`, which above adds
  # softmmu targets that a user-only build rejects; vanilla also hits the cache.
  qemu-user = super.qemu.override { userOnly = true; };
}

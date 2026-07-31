{
  lib,
  pkgs,
  inputs,
  config,
  ...
}:
{
  options.custom.kernel = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to use the shared kernel configuration across Linux hosts";
    };

    useBorePatches = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to apply BORE scheduler patches to the kernel";
    };
  };

  config = lib.mkIf config.custom.kernel.enable {
    # Kernel version used across all Linux hosts
    boot.kernelPackages = pkgs.linuxPackages_7_1;

    boot.kernelPatches =
      let
        # Use pkgs.linuxPackages_7_1.kernel.version instead of config.boot.kernelPackages.kernel.version
        # to avoid infinite recursion (boot.kernelPatches affects boot.kernelPackages)
        kernelVersion = pkgs.linuxPackages_7_1.kernel.version;
        # Stable BORE series still targets 7.1-rc1 and rots on 7.1.5; use the
        # exact-version testing patch until upstream promotes a stable series.
        testingPatch = "${inputs.bore-scheduler-src}/patches/testing/0001-linux${kernelVersion}-bore-6.8.0.patch";

        borePatches = lib.optionals config.custom.kernel.useBorePatches [
          {
            name = "bore-testing-${kernelVersion}";
            patch = testingPatch;
          }
        ];
      in
      borePatches;
  };
}

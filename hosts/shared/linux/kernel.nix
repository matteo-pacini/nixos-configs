{
  lib,
  pkgs,
  inputs,
  config,
  ...
}:
{
  options.shared.kernel = {
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

  config = lib.mkIf config.shared.kernel.enable {
    # Kernel version used across all Linux hosts
    boot.kernelPackages = pkgs.linuxPackages_6_17;

    # BORE scheduler patches
    boot.kernelPatches = lib.mkIf config.shared.kernel.useBorePatches (
      let
        # Use pkgs.linuxPackages_6_17.kernel.version instead of config.boot.kernelPackages.kernel.version
        # to avoid infinite recursion (boot.kernelPatches affects boot.kernelPackages)
        kernelVersion = lib.versions.majorMinor pkgs.linuxPackages_6_17.kernel.version;
        patchesDir = "${inputs.bore-scheduler-src}/patches/stable/linux-${kernelVersion}-bore";
      in
      lib.mapAttrsToList (name: _: {
        name = "bore-${name}";
        patch = "${patchesDir}/${name}";
      }) (builtins.readDir patchesDir)
    );
  };
}

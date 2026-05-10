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
    boot.kernelPackages = pkgs.linuxPackages_7_0;

    boot.kernelPatches =
      let
        # Use pkgs.linuxPackages_7_0.kernel.version instead of config.boot.kernelPackages.kernel.version
        # to avoid infinite recursion (boot.kernelPatches affects boot.kernelPackages)
        kernelVersion = lib.versions.majorMinor pkgs.linuxPackages_7_0.kernel.version;
        patchesDir = "${inputs.bore-scheduler-src}/patches/stable/linux-${kernelVersion}-bore";

        borePatches = lib.optionals config.custom.kernel.useBorePatches (
          lib.mapAttrsToList (name: _: {
            name = "bore-${name}";
            patch = "${patchesDir}/${name}";
          }) (builtins.readDir patchesDir)
        );

        # CVE-2026-43284 (Dirty Frag, ESP half): xfrm decrypts in place over
        # MSG_SPLICE_PAGES-backed frags an unprivileged process still owns.
        # Drop once nixpkgs bumps linuxPackages_7_0 past 7.0.3.
        # Copy Fail (CVE-2026-31431) is already applied in 7.0.3 source.
        # Dirty Frag RxRPC half (CVE-2026-43500) has no upstream patch yet.
        dirtyFragEspPatch = {
          name = "CVE-2026-43284-xfrm-esp-no-inplace-shared-frags";
          patch = pkgs.fetchpatch {
            url = "https://github.com/torvalds/linux/commit/f4c50a4034e62ab75f1d5cdd191dd5f9c77fdff4.patch";
            hash = "sha256-68d7/BoMYHWVBY8btrr8yuObhkGod1Hwj5Ny2CZt+qk=";
          };
        };
      in
      [ dirtyFragEspPatch ] ++ borePatches;
  };
}

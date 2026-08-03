{
  lib,
  pkgs,
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
  };

  config = lib.mkIf config.custom.kernel.enable {
    # Kernel version used across all Linux hosts
    boot.kernelPackages = pkgs.linuxPackages_7_1;
  };
}

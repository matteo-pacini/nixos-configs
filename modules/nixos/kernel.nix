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
    boot.kernelPackages = pkgs.linuxPackages_7_3;
  };
}

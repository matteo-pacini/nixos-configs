{
  config,
  pkgs,
  lib,
  ...
}:
{
  boot.kernel.sysctl = {
    "vm.max_map_count" = "1048576";
  };

  hardware.steam-hardware.enable = true;

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  services.xserver.videoDrivers = [ "nvidia" ];

  programs.steam.enable = true;
}

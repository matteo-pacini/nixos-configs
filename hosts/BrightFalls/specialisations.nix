{ lib, ... }:
{
  # WiFi specialisation - enables WiFi by removing the kernel module blacklist
  specialisation."wifi".configuration = {
    system.nixos.tags = [ "with-wifi" ];

    # Remove the WiFi driver from the blacklist
    boot.blacklistedKernelModules = lib.mkForce [ ];
  };
}

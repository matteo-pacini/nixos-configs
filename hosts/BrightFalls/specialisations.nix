{ lib, ... }:
{
  # WiFi specialisation - enables WiFi by removing the kernel module blacklist
  specialisation."wifi".configuration = {
    system.nixos.tags = [ "with-wifi" ];

    # Remove the WiFi driver from the blacklist
    boot.blacklistedKernelModules = lib.mkForce [ ];
  };

  # UMIP-disabled specialisation - some older games/drivers (e.g. under
  # Wine/VMware) fault on UMIP. Name form (not clearcpuid=514) is stable
  # across kernel versions; numeric IDs track internal feature-word layout.
  specialisation."without-umip".configuration = {
    system.nixos.tags = [ "without-umip" ];

    boot.kernelParams = [ "clearcpuid=umip" ];
  };
}

{
  lib,
  isVM,
  ...
}:
{
  # WiFi specialisation - enables WiFi by removing the kernel module blacklist
  # Use optionalAttrs to prevent the specialisation from being created in VMs
  specialisation = lib.optionalAttrs (!isVM) {
    "wifi".configuration = {
      system.nixos.tags = [ "with-wifi" ];

      # Remove the WiFi driver from the blacklist
      boot.blacklistedKernelModules = lib.mkForce [ ];
    };
  };
}

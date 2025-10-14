{ ... }:
{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/vda";
        content = {
          type = "gpt";
          partitions = {
            # Part 1: EFI Boot partition - 1GB - FAT32
            boot = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "defaults" ];
                extraArgs = [
                  "-n"
                  "BOOT"
                ]; # Label for FAT32
              };
            };
            # Part 2: Swap - 4GB
            swap = {
              size = "4G";
              type = "8200";
              content = {
                type = "swap";
                randomEncryption = false;
                extraArgs = [
                  "-L"
                  "SWAP"
                ]; # Label for swap
              };
            };
            # Part 3: Root - remaining space - XFS
            root = {
              size = "100%";
              type = "8300";
              content = {
                type = "filesystem";
                format = "xfs";
                mountpoint = "/";
                mountOptions = [
                  "defaults"
                  "noatime"
                ];
                extraArgs = [
                  "-L"
                  "ROOT"
                ]; # Label for XFS
              };
            };
          };
        };
      };
    };
  };
}

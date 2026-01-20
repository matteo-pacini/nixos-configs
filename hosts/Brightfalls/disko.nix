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
              label = "BOOT";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "defaults" ];
                extraArgs = [
                  "-n"
                  "BOOT"
                ]; # Filesystem label for FAT32
              };
            };
            # Part 2: Swap - 4GB
            swap = {
              size = "4G";
              type = "8200";
              label = "SWAP";
              content = {
                type = "swap";
                randomEncryption = false;
                extraArgs = [
                  "-L"
                  "SWAP"
                ]; # Filesystem label for swap
              };
            };
            # Part 3: Root - remaining space - ext4
            root = {
              size = "100%";
              type = "8300";
              label = "ROOT";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
                mountOptions = [
                  "defaults"
                  "noatime"
                ];
                extraArgs = [
                  "-L"
                  "ROOT"
                ]; # Filesystem label for ext4
              };
            };
          };
        };
      };
    };
  };
}

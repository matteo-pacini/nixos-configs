# Disk configuration for BrightFalls (physical machine)
#
# Hardware: Minisforum UM890 Pro (Zen4) + DEG1 eGPU Dock
# Single 4TB NVMe, unencrypted (gaming PC), dual-boot with Windows 11.
#
# Layout:
#   - boot:  1GB    vfat   EFI System Partition (shared with Windows)
#   - swap:  36GB   swap   Hibernation support
#   - root:  200GB  ext4   NixOS system
#   - home:  600GB  ext4   Configs & code repos
#   - msr:   16MB   -      Microsoft Reserved (Windows 11)
#   - win:   512GB  ntfs   Windows 11 (unformatted; Win installer formats)
#   - games: ~2.5TB xfs    Steam library
#
# Install:
#   1. Set `device` below to the real NVMe by-id path.
#   2. sudo disko --mode destroy,format,mount   (WIPES DISK, incl. Windows)
#   3. sudo nixos-install --flake ...
#   4. Boot a Windows 11 USB, install into the 512G unformatted slot.
#
{ ... }:
{
  disko.devices = {
    disk = {
      nvme = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-CT4000P310SSD8_25184FF48CDC";
        content = {
          type = "gpt";
          partitions = {

            # Part 1: EFI Boot partition - 1GB - vfat (shared with Windows)
            boot = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };

            # Part 2: Swap partition - 36GB (hibernation: RAM + headroom)
            swap = {
              size = "36G";
              content = {
                type = "swap";
              };
            };

            # Part 3: Root partition - 200GB - ext4
            root = {
              size = "200G";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
                mountOptions = [
                  "defaults"
                  "noatime"
                ];
              };
            };

            # Part 4: Home partition - 600GB - ext4
            home = {
              size = "600G";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/home";
                mountOptions = [
                  "defaults"
                  "noatime"
                ];
              };
            };

            # Part 5: Microsoft Reserved - 16MB - no filesystem (Windows 11)
            msr = {
              size = "16M";
              type = "0C01";
            };

            # Part 6: Windows 11 - 512GB - NTFS, unformatted
            # Left unformatted; the Windows installer creates the NTFS
            # filesystem here and its own WinRE recovery partition.
            windows = {
              size = "512G";
              type = "0700";
            };

            # Part 7: Games partition - remaining space (~2.5TB) - XFS
            games = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "xfs";
                mountpoint = "/mnt/games";
                mountOptions = [
                  "defaults"
                  "noatime"
                ];
              };
            };

          };
        };
      };
    };
  };
}

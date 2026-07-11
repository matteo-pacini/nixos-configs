# Disk configuration for BrightFalls (physical machine)
#
# Hardware: Minisforum UM890 Pro (Zen4) + DEG1 eGPU Dock
# Single 4TB NVMe, full-disk encryption: one LUKS2 container holding an
# LVM volume group, so volumes can be resized later (lvresize + resize2fs)
# without touching the partition table or the LUKS layer.
#
# Layout:
#   - boot: 1GB   vfat  EFI System Partition
#   - luks: rest  LUKS2 "cryptroot" (AES-256-XTS, argon2id)
#       └ LVM VG "brightfalls"
#           - root:  200GB    ext4  NixOS system
#           - home:  600GB    ext4  Configs & code repos
#           - swap:  36GB     swap  Hibernation support
#           - games: ~2.8TB   ext4  Steam library
#
# Security:
#   - LUKS2 with argon2id (4GB memory) — brute-force hostile
#   - AES-256-XTS (--key-size 512): ~128-bit effective post-Grover,
#     i.e. quantum-resistant; purely symmetric, no TPM/PKI involved
#   - LVM lives *inside* the container: volume names/sizes not visible at rest
#
# Install:
#   1. Set `device` below to the real NVMe by-id path.
#   2. echo -n '<passphrase>' > /tmp/luks.password
#   3. sudo disko --mode destroy,format,mount   (WIPES DISK)
#   4. sudo nixos-install --flake ...
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

            # Part 1: EFI Boot partition - 1GB - vfat
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

            # Part 2: LUKS2 container - rest of disk - LVM inside
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "cryptroot";
                # Install-time only; boot unlock prompts for the passphrase
                passwordFile = "/tmp/luks.password";
                settings = {
                  allowDiscards = true;
                };
                extraFormatArgs = [
                  "--type"
                  "luks2"
                  "--cipher"
                  "aes-xts-plain64"
                  "--hash"
                  "sha512"
                  "--key-size"
                  "512"
                  "--pbkdf"
                  "argon2id"
                  "--pbkdf-memory"
                  "4194304"
                  "--pbkdf-parallel"
                  "4"
                  "--iter-time"
                  "3000"
                  "--sector-size"
                  "4096"
                ];
                content = {
                  type = "lvm_pv";
                  vg = "brightfalls";
                };
              };
            };

          };
        };
      };
    };

    lvm_vg = {
      brightfalls = {
        type = "lvm_vg";
        lvs = {

          # Root volume - 200GB - ext4
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

          # Home volume - 600GB - ext4
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

          # Swap volume - 36GB (hibernation: RAM + headroom)
          swap = {
            size = "36G";
            content = {
              type = "swap";
              resumeDevice = true;
            };
          };

          # Games volume - remaining space (~2.8TB) - ext4
          # ext4 (not xfs) so it can shrink as well as grow
          games = {
            size = "100%FREE";
            content = {
              type = "filesystem";
              format = "ext4";
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
}

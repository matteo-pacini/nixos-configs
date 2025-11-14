# Disk configuration for BrightFalls (physical machine)
#
# Physical Disks (by size):
#   1TB  Samsung 860 EVO (S4X6NJ0N406662R)  - OS disk
#   512GB Samsung 850 PRO (S250NXAG978494H) - Games disk 1
#   256GB Samsung 840 PRO (S1ATNSADA34160X) - Games disk 2
#
# Layout:
#   os-disk (1TB Samsung 860 EVO): Operating System
#     - part1: /boot (512MB, vfat, unencrypted)
#     - part2: /vault (48MB, LUKS encrypted ext2, password-unlocked)
#              Contains keyfile for auto-unlocking root and game disks
#              Uses paranoid security: Serpent cipher, SHA512, 3000ms iter-time, 4GB PBKDF memory
#     - part3: swap (32GB, random encryption - new key on every boot)
#     - part4: root (remaining ~899GB, LUKS encrypted btrfs with keyfile from vault)
#              Subvolumes: @, @home, @nix, @log, @cache, @snapshots
#
#   games-disk-1 (512GB Samsung 850 PRO): Games storage
#     - part1: LUKS encrypted ext4, auto-unlocked with keyfile from vault
#
#   games-disk-2 (256GB Samsung 840 PRO): Games storage
#     - part1: LUKS encrypted ext4, auto-unlocked with keyfile from vault
#
# Boot sequence:
#   1. Swap gets random encryption key (ephemeral, no password needed)
#   2. User enters password to unlock vault (os-disk part2)
#   3. Vault mounts at /vault, making /vault/luks.key available
#   4. Root (os-disk part4) auto-unlocks using /vault/luks.key
#   5. System boots and mounts btrfs subvolumes
#   6. Game disks auto-unlock using /vault/luks.key
#
# Security Strategy:
#   - Vault: Maximum security (Serpent-XTS, SHA512, Argon2id with 4GB memory)
#   - Other volumes: Standard security (AES-XTS, SHA256, Argon2id with default memory)
#   - The keyfile /vault/luks.key is automatically generated during disko formatting
#   - All LUKS volumes except vault use this keyfile for automatic unlocking
#   - Vault is the only volume requiring password entry at boot
#
{ ... }:
{
  disko.devices = {
    disk = {
      # ============================================================================
      # OS Disk - 1TB Samsung 860 EVO (S4X6NJ0N406662R)
      # ============================================================================
      a-os-disk = {
        type = "disk";
        device = "/dev/disk/by-id/ata-Samsung_SSD_860_EVO_1TB_S4X6NJ0N406662R";
        content = {
          type = "gpt";
          partitions = {
            # EFI Boot partition - 512MB - Unencrypted
            boot = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };

            # Vault partition - 48MB - LUKS encrypted with password
            # Contains the keyfile used to unlock all other LUKS volumes
            # Uses paranoid security settings: Serpent cipher, SHA512, high iteration time
            vault = {
              size = "48M";
              content = {
                type = "luks";
                name = "cryptvault";
                # Password file for disko installation (will prompt for password at boot)
                passwordFile = "/tmp/vault.passwordFile";
                initrdUnlock = true;
                settings = {
                  allowDiscards = true;
                  # No keyFile - will prompt for password during boot
                };
                extraFormatArgs = [
                  "--type"
                  "luks2"
                  "--cipher"
                  "serpent-xts-plain64"
                  "--hash"
                  "sha512"
                  "--iter-time"
                  "3000"
                  "--key-size"
                  "256"
                  "--pbkdf"
                  "argon2id"
                  "--pbkdf-memory"
                  "4194304"
                  "--sector-size"
                  "4096"
                ];
                content = {
                  type = "filesystem";
                  format = "ext2";
                  extraArgs = [
                    "-F"
                    "-L"
                    "vault"
                    "-m"
                    "0"
                    "-N"
                    "128"
                    "-b"
                    "4096"
                  ];
                  mountpoint = "/vault";
                  mountOptions = [
                    "noatime"
                    "errors=remount-ro"
                  ];
                  postCreateHook = ''
                    echo "Copying keyfile to vault..."
                    MNTPOINT=$(mktemp -d)
                    mount /dev/mapper/cryptvault $MNTPOINT
                    cp /tmp/luks.key $MNTPOINT/luks.key
                    chmod 400 $MNTPOINT/luks.key
                    umount $MNTPOINT
                    rmdir $MNTPOINT
                  '';
                };
              };
            };

            # Swap partition - 32GB - Random encryption (new key on every boot)
            swap = {
              size = "32G";
              content = {
                type = "swap";
                randomEncryption = true;
              };
            };

            # Root partition - Remaining space (~899GB)
            # LUKS encrypted, auto-unlocked with keyfile from vault
            root = {
              size = "100%";
              content = {
                type = "luks";
                name = "cryptroot";
                passwordFile = "/tmp/luks.key";
                initrdUnlock = true;
                # Settings passed to boot.initrd.luks.devices.cryptroot
                # Note: keyFile is set in hardware.nix, not here, to avoid overriding passwordFile during formatting
                settings = {
                  allowDiscards = true;
                };
                extraFormatArgs = [
                  "--type"
                  "luks2"
                  "--cipher"
                  "aes-xts-plain64"
                  "--hash"
                  "sha256"
                  "--iter-time"
                  "1000"
                  "--key-size"
                  "512"
                  "--pbkdf"
                  "argon2id"
                  "--sector-size"
                  "4096"
                ];
                content = {
                  type = "btrfs";
                  extraArgs = [
                    "--force"
                    "--label"
                    "nixos"
                  ];
                  subvolumes = {
                    # Root subvolume
                    "@" = {
                      mountpoint = "/";
                      mountOptions = [
                        "compress=zstd:1"
                        "noatime"
                        "ssd"
                        "space_cache=v2"
                      ];
                    };
                    # Home subvolume
                    "@home" = {
                      mountpoint = "/home";
                      mountOptions = [
                        "compress=zstd:1"
                        "noatime"
                        "ssd"
                        "space_cache=v2"
                      ];
                    };
                    # Nix store subvolume
                    "@nix" = {
                      mountpoint = "/nix";
                      mountOptions = [
                        "compress=zstd:1"
                        "noatime"
                        "ssd"
                        "space_cache=v2"
                      ];
                    };
                    # Log subvolume (no compression, excluded from snapshots)
                    "@log" = {
                      mountpoint = "/var/log";
                      mountOptions = [
                        "noatime"
                        "ssd"
                        "space_cache=v2"
                      ];
                    };
                    # Cache subvolume (no compression, excluded from snapshots)
                    "@cache" = {
                      mountpoint = "/var/cache";
                      mountOptions = [
                        "noatime"
                        "ssd"
                        "space_cache=v2"
                      ];
                    };
                    # Snapshots subvolume
                    "@snapshots" = {
                      mountpoint = "/.snapshots";
                      mountOptions = [
                        "noatime"
                        "ssd"
                        "space_cache=v2"
                      ];
                    };
                  };
                };
              };
            };
          };
        };
      };

      # ============================================================================
      # Games Disk 1 - 512GB Samsung 850 PRO (S250NXAG978494H)
      # ============================================================================
      b-games-disk-1 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-Samsung_SSD_850_PRO_512GB_S250NXAG978494H";
        content = {
          type = "gpt";
          partitions = {
            games1 = {
              size = "100%";
              content = {
                type = "luks";
                name = "cryptgames1";
                passwordFile = "/tmp/luks.key";
                initrdUnlock = false;
                # Settings for systemd-cryptsetup (unlocked after boot)
                # Note: keyFile will be read from /etc/crypttab which references /vault/luks.key
                settings = {
                  allowDiscards = true;
                };
                extraFormatArgs = [
                  "--type"
                  "luks2"
                  "--cipher"
                  "aes-xts-plain64"
                  "--hash"
                  "sha256"
                  "--iter-time"
                  "1000"
                  "--key-size"
                  "512"
                  "--pbkdf"
                  "argon2id"
                  "--sector-size"
                  "4096"
                ];
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/mnt/games1";
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

      # ============================================================================
      # Games Disk 2 - 256GB Samsung 840 PRO (S1ATNSADA34160X)
      # ============================================================================
      c-games-disk-2 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-Samsung_SSD_840_PRO_Series_S1ATNSADA34160X";
        content = {
          type = "gpt";
          partitions = {
            games2 = {
              size = "100%";
              content = {
                type = "luks";
                name = "cryptgames2";
                passwordFile = "/tmp/luks.key";
                initrdUnlock = false;
                # Settings for systemd-cryptsetup (unlocked after boot)
                # Note: keyFile will be read from /etc/crypttab which references /vault/luks.key
                settings = {
                  allowDiscards = true;
                };
                extraFormatArgs = [
                  "--type"
                  "luks2"
                  "--cipher"
                  "aes-xts-plain64"
                  "--hash"
                  "sha256"
                  "--iter-time"
                  "1000"
                  "--key-size"
                  "512"
                  "--pbkdf"
                  "argon2id"
                  "--sector-size"
                  "4096"
                ];
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/mnt/games2";
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
  };
}

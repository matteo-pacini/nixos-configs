# Disk configuration for BrightFalls (physical machine)
#
# Physical Disks (by size):
#   1TB  Samsung 860 EVO (S4X6NJ0N406662R)  - OS disk
#   512GB Samsung 850 PRO (S250NXAG978494H) - Games disk 1
#
# Layout:
#   os-disk (1TB Samsung 860 EVO): Operating System
#     - part1: /boot (512MB, vfat, unencrypted)
#     - part2: /vault (48MB, LUKS encrypted ext2, password-unlocked)
#              Contains keyfile for auto-unlocking root and game disks
#              Security: Serpent-XTS cipher, SHA512 hash, 3000ms iter-time, 4GB Argon2id memory
#     - part3: swap (32GB, random encryption - new key on every boot)
#     - part4: root (remaining ~899GB, LUKS encrypted btrfs with keyfile from vault)
#              Security: AES-XTS cipher, SHA256 hash, 1000ms iter-time, Argon2id PBKDF
#              Subvolumes: @, @home, @nix, @log, @cache, @snapshots
#
#   games-disk-1 (512GB Samsung 850 PRO): Games storage
#     - part1: LUKS encrypted ext4, auto-unlocked with keyfile from vault
#              Security: AES-XTS cipher, SHA256 hash, 1000ms iter-time, Argon2id PBKDF
#
# Boot sequence:
#   1. Swap gets random encryption key (ephemeral, no password needed)
#   2. User enters password to unlock vault (os-disk part2)
#   3. Vault mounts at /vault, making /vault/luks.key available
#   4. Root (os-disk part4) auto-unlocks using /vault/luks.key
#   5. System boots and mounts btrfs subvolumes
#   6. Game disks auto-unlock using /vault/luks.key (via /etc/crypttab)
#
# Security Strategy:
#   VAULT (Maximum Security - Quantum-Resistant):
#     - Cipher: Serpent-XTS-plain64 (256-bit key, quantum-resistant)
#     - Hash: SHA512 (stronger than SHA256)
#     - Iterations: 3000ms (3x longer than standard, increases brute-force resistance)
#     - PBKDF: Argon2id with 4GB memory (4194304 KiB, maximum security)
#     - Key size: 256 bits
#     - Sector size: 4096 bytes (modern SSD alignment)
#     - Rationale: Vault contains the master keyfile; maximum security justified
#
#   ROOT & GAMES (Standard Security - Performance Balanced):
#     - Cipher: AES-XTS-plain64 (512-bit key, hardware-accelerated on modern CPUs)
#     - Hash: SHA256 (standard, sufficient for non-vault volumes)
#     - Iterations: 1000ms (standard, good balance of security and performance)
#     - PBKDF: Argon2id with default memory (sufficient for keyfile-based unlocking)
#     - Key size: 512 bits (maximum for AES-XTS)
#     - Sector size: 4096 bytes (modern SSD alignment)
#     - Rationale: Keyfile-based unlocking is faster; standard security sufficient
#
#   SWAP (Ephemeral Encryption):
#     - Random key generated on every boot
#     - No persistent encryption needed (data not sensitive between reboots)
#
#   Implementation Notes:
#     - The keyfile /vault/luks.key is automatically generated during disko formatting
#     - All LUKS volumes except vault use this keyfile for automatic unlocking
#     - Vault is the only volume requiring password entry at boot
#     - Games disks are unlocked in stage 2 (after boot) via /etc/crypttab
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
            # Uses maximum security settings: Serpent cipher (quantum-resistant),
            # SHA512 hash, 3000ms iterations, and 4GB Argon2id memory
            vault = {
              size = "48M";
              content = {
                type = "luks";
                name = "cryptvault";
                passwordFile = "/tmp/vault.passwordFile";
                initrdUnlock = true;
                settings = {
                  allowDiscards = true;
                };
                extraFormatArgs = [
                  "--type"
                  "luks2"
                  # Serpent-XTS: Quantum-resistant block cipher (256-bit key)
                  # More conservative than AES, suitable for long-term security
                  "--cipher"
                  "serpent-xts-plain64"
                  # SHA512: Stronger hash than SHA256, increases KDF security
                  "--hash"
                  "sha512"
                  # 3000ms: 3x longer than standard (1000ms), increases brute-force resistance
                  # Acceptable for vault since it's only unlocked once at boot
                  "--iter-time"
                  "3000"
                  # 256-bit key: Standard for Serpent-XTS
                  "--key-size"
                  "256"
                  # Argon2id: Memory-hard KDF resistant to GPU/ASIC attacks
                  "--pbkdf"
                  "argon2id"
                  # 4GB memory: Maximum security for key derivation
                  # Increases resistance to parallel attacks
                  "--pbkdf-memory"
                  "4194304"
                  # 4096-byte sectors: Modern SSD alignment, improves performance
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
            # Uses standard security settings: AES cipher (hardware-accelerated),
            # SHA256 hash, 1000ms iterations, Argon2id PBKDF
            root = {
              size = "100%";
              content = {
                type = "luks";
                name = "cryptroot";
                initrdUnlock = true;
                settings = {
                  allowDiscards = true;
                  keyFile = "/tmp/luks.key";
                };
                extraFormatArgs = [
                  "--type"
                  "luks2"
                  # AES-XTS: Industry standard, hardware-accelerated on modern CPUs
                  # Faster than Serpent, sufficient security for keyfile-based unlocking
                  "--cipher"
                  "aes-xts-plain64"
                  # SHA256: Standard hash, sufficient for non-vault volumes
                  "--hash"
                  "sha256"
                  # 1000ms: Standard iteration time, good balance of security and performance
                  # Keyfile-based unlocking is fast, so standard iterations are acceptable
                  "--iter-time"
                  "1000"
                  # 512-bit key: Maximum for AES-XTS, provides strong encryption
                  "--key-size"
                  "512"
                  # Argon2id: Memory-hard KDF resistant to GPU/ASIC attacks
                  "--pbkdf"
                  "argon2id"
                  # 4096-byte sectors: Modern SSD alignment, improves performance
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
                    "@" = {
                      mountpoint = "/";
                      mountOptions = [
                        "compress=zstd:1"
                        "noatime"
                        "ssd"
                        "space_cache=v2"
                      ];
                    };
                    "@home" = {
                      mountpoint = "/home";
                      mountOptions = [
                        "compress=zstd:1"
                        "noatime"
                        "ssd"
                        "space_cache=v2"
                      ];
                    };
                    "@nix" = {
                      mountpoint = "/nix";
                      mountOptions = [
                        "compress=zstd:1"
                        "noatime"
                        "ssd"
                        "space_cache=v2"
                      ];
                    };
                    "@log" = {
                      mountpoint = "/var/log";
                      mountOptions = [
                        "noatime"
                        "ssd"
                        "space_cache=v2"
                      ];
                    };
                    "@cache" = {
                      mountpoint = "/var/cache";
                      mountOptions = [
                        "noatime"
                        "ssd"
                        "space_cache=v2"
                      ];
                    };
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
      # Unlocked in stage 2 (after boot) via /etc/crypttab with keyfile from vault
      # Uses standard security settings matching root partition
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
                # initrdUnlock = false: Unlocked in stage 2 via /etc/crypttab
                # This allows faster boot and reduces initrd complexity
                initrdUnlock = false;
                settings = {
                  allowDiscards = true;
                  keyFile = "/tmp/luks.key";
                };
                extraFormatArgs = [
                  "--type"
                  "luks2"
                  # AES-XTS: Same as root partition for consistency
                  "--cipher"
                  "aes-xts-plain64"
                  # SHA256: Standard hash
                  "--hash"
                  "sha256"
                  # 1000ms: Standard iteration time
                  "--iter-time"
                  "1000"
                  # 512-bit key: Maximum for AES-XTS
                  "--key-size"
                  "512"
                  # Argon2id: Memory-hard KDF
                  "--pbkdf"
                  "argon2id"
                  # 4096-byte sectors: Modern SSD alignment
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
    };
  };
}

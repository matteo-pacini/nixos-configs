# Disk configuration for BrightFalls (physical machine)
#
# Hardware: Minisforum UM890 Pro (Zen4) + DEG1 eGPU Dock
#
# Physical Disk:
#   4TB NVMe - Single system disk
#
# Layout:
#   - boot:  1GB    vfat   EFI System Partition (unencrypted)
#   - vault: 64MB   ext2   Keyfile storage (LUKS2, password, Serpent-XTS)
#   - swap:  36GB   swap   Hibernation support (LUKS2, keyfile)
#   - root:  200GB  ext4   NixOS system (LUKS2, keyfile)
#   - home:  1TB    ext4   Configs & code repos (LUKS2, keyfile)
#   - games: ~2.7TB XFS    Steam library (LUKS2, keyfile)
#
# Boot sequence:
#   1. User enters password → vault unlocks (Serpent-XTS, 4GB Argon2id)
#   2. Vault mounts at /vault → keyfile becomes available
#   3. swap/root/games auto-unlock using /vault/luks.key
#   4. Hibernation supported (persistent swap encryption)
#
# Security Strategy:
#   VAULT (Maximum Security):
#     - Cipher: Serpent-XTS-plain64 (256-bit, higher security margin than AES)
#     - Hash: SHA512
#     - PBKDF: Argon2id with 4GB memory, 4 parallel threads
#     - Iterations: 3000ms
#
#   SWAP/ROOT/GAMES (Standard Security):
#     - Cipher: AES-XTS-plain64 (512-bit, hardware-accelerated)
#     - Hash: SHA256
#     - PBKDF: Argon2id with 2GB memory, 4 parallel threads
#     - Iterations: 2000ms
#
# Installation:
#   1. Create password file: echo -n "your-password" > /tmp/vault.key
#   2. Generate keyfile: dd if=/dev/urandom of=/tmp/luks.key bs=4096 count=1 iflag=fullblock
#   3. Run disko: sudo nix run github:nix-community/disko -- --mode destroy,format,mount ...
#   4. Install: sudo nixos-install --flake ...
#
{ ... }:
{
  disko.devices = {
    disk = {
      nvme = {
        type = "disk";
        # TODO: Replace with actual NVMe device ID after booting installer
        # Use: ls -l /dev/disk/by-id/ | grep nvme
        device = "/dev/disk/by-id/PLACEHOLDER";
        content = {
          type = "gpt";
          partitions = {

            # Part 1: EFI Boot partition - 1GB - vfat (unencrypted)
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

            # Part 2: Vault partition - 64MB - ext2 on LUKS2
            # Password-protected, stores keyfile for other volumes
            vault = {
              size = "64M";
              content = {
                type = "luks";
                name = "cryptvault";
                passwordFile = "/tmp/vault.key";
                initrdUnlock = true;
                settings = {
                  allowDiscards = true;
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
                  "--pbkdf-parallel"
                  "4"
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

            # Part 3: Swap partition - 36GB - swap on LUKS2
            # Persistent encryption for hibernation (RAM + 4GB headroom)
            swap = {
              size = "36G";
              content = {
                type = "luks";
                name = "cryptswap";
                initrdUnlock = true;
                settings = {
                  keyFile = "/tmp/luks.key";
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
                  "2000"
                  "--key-size"
                  "512"
                  "--pbkdf"
                  "argon2id"
                  "--pbkdf-memory"
                  "2097152"
                  "--pbkdf-parallel"
                  "4"
                  "--sector-size"
                  "4096"
                ];
                content = {
                  type = "swap";
                };
              };
            };

            # Part 4: Root partition - 200GB - ext4 on LUKS2
            # Best for Nix store (small files, hardlinks)
            root = {
              size = "200G";
              content = {
                type = "luks";
                name = "cryptroot";
                initrdUnlock = true;
                settings = {
                  keyFile = "/tmp/luks.key";
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
                  "2000"
                  "--key-size"
                  "512"
                  "--pbkdf"
                  "argon2id"
                  "--pbkdf-memory"
                  "2097152"
                  "--pbkdf-parallel"
                  "4"
                  "--sector-size"
                  "4096"
                ];
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
            };

            # Part 5: Home partition - 1TB - ext4 on LUKS2
            # Best for configs & code repos (small files, hardlinks)
            home = {
              size = "1T";
              content = {
                type = "luks";
                name = "crypthome";
                initrdUnlock = true;
                settings = {
                  keyFile = "/tmp/luks.key";
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
                  "2000"
                  "--key-size"
                  "512"
                  "--pbkdf"
                  "argon2id"
                  "--pbkdf-memory"
                  "2097152"
                  "--pbkdf-parallel"
                  "4"
                  "--sector-size"
                  "4096"
                ];
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
            };

            # Part 6: Games partition - remaining space (~2.7TB) - XFS on LUKS2
            # Best for large files (games), parallel I/O
            games = {
              size = "100%";
              content = {
                type = "luks";
                name = "cryptgames";
                initrdUnlock = true;
                settings = {
                  keyFile = "/tmp/luks.key";
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
                  "2000"
                  "--key-size"
                  "512"
                  "--pbkdf"
                  "argon2id"
                  "--pbkdf-memory"
                  "2097152"
                  "--pbkdf-parallel"
                  "4"
                  "--sector-size"
                  "4096"
                ];
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
  };
}

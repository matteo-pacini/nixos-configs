self: super:
let
  optimizedForBrightFalls =
    pkg:
    pkg.overrideAttrs (oldAttrs: {
      env = (oldAttrs.env or { }) // {
        NIX_CFLAGS_COMPILE = (oldAttrs.env.NIX_CFLAGS_COMPILE or "") + " -O2 -march=znver4 -mtune=znver4";
        NIX_CXXFLAGS_COMPILE = (oldAttrs.env.NIX_CFLAGS_COMPILE or "") + " -O2 -march=znver4 -mtune=znver4";
      };
    });
in
{
  reshade-linux = super.callPackage ../packages/reshade-linux { };
  exiled-exchange-2 = super.callPackage ../packages/exiled-exchange-2.nix { };
  path-of-building-poe2 = super.callPackage ../packages/path-of-building-poe2.nix { };
  linuwux-runtime = super.callPackage ../packages/linuwux-runtime.nix { };
  plymouth-brightfalls = super.callPackage ../packages/plymouth-brightfalls { };

  # GDM 50.2's hardened pam_gdm rejects any kernel-keyring payload whose last
  # byte is not NUL — but systemd deliberately strips that trailing NUL from
  # the LUKS passphrase it caches (ask-password-api.c, add_to_keyring). Result:
  # autologin no longer unlocks the login keyring on this LUKS+autologin host
  # (worked on gdm 50.1). See the patch header for the full write-up.
  # Upstream: https://gitlab.gnome.org/GNOME/gdm/-/issues/1091
  # Fixed upstream in gdm 50.3, but nixpkgs is still on 50.2. Drop this
  # override (and patches/gdm/) once nixos-unstable ships gdm >= 50.3 — check
  # the journal for "gkr-pam: ... unlocked keyring" after a clean boot without it.
  # WAIT-FOR version: gdm >= 50.3
  gdm = super.gdm.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ../patches/gdm/001-pam-gdm-accept-unterminated-cached-passphrase.patch
    ];
  });

  qemu = optimizedForBrightFalls (
    super.qemu.override ({
      hostCpuTargets = [
        "i386-softmmu"
        "x86_64-softmmu"
        "aarch64-softmmu"
      ];
    })
  );

  # OVMF/OVMFFull run QEMU during build to generate UEFI vars. Vanilla QEMU
  # keeps them identical to the cached builds, and a znver4 QEMU could not run
  # on builders without those CPU features.
  OVMF = super.OVMF.override { qemu = super.qemu; };
  OVMFFull = super.OVMFFull.override { qemu = super.qemu; };

  # binfmt's interpreter. nixpkgs derives it from `qemu`, which above adds
  # softmmu targets that a user-only build rejects; vanilla also hits the cache.
  qemu-user = super.qemu.override { userOnly = true; };
}

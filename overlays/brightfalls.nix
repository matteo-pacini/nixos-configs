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
  ci-fixer-test = super.runCommand "ci-fixer-test" { } ''
    echo ok > $out/share/ci-fixer-test/ok
  '';

  # GDM 50.2's hardened pam_gdm rejects any kernel-keyring payload whose last
  # byte is not NUL — but systemd deliberately strips that trailing NUL from
  # the LUKS passphrase it caches (ask-password-api.c, add_to_keyring). Result:
  # autologin no longer unlocks the login keyring on this LUKS+autologin host
  # (worked on gdm 50.1). See the patch header for the full write-up.
  # Upstream: https://gitlab.gnome.org/GNOME/gdm/-/issues/1091
  # Drop this override (and patches/gdm/) once nixos-unstable ships a gdm
  # release with an upstream fix — check the journal for
  # "gkr-pam: ... unlocked keyring" after a clean boot without it.
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

  # OVMF/OVMFFull run QEMU during build to generate UEFI vars.
  # Use vanilla QEMU to avoid znver4 instructions failing in TCG emulation.
  # See: https://github.com/NixOS/nixpkgs/issues/381223
  OVMF = super.OVMF.override { qemu = super.qemu; };
  OVMFFull = super.OVMFFull.override { qemu = super.qemu; };

  # binfmt's interpreter. nixpkgs derives it from `qemu`, which above adds
  # softmmu targets that a user-only build rejects; vanilla also hits the cache.
  qemu-user = super.qemu.override { userOnly = true; };

  # typescript-language-server 6.0.2 landed in nixpkgs with a stale pnpmDeps
  # hash (pulled in by nvf's typescript language support). Drop once
  # nixos-unstable includes the upstream fix, i.e. once
  #   gh api repos/NixOS/nixpkgs/compare/ac7b1aaed0...nixos-unstable -q .status
  # reports "ahead" or "identical".
  # Fix: https://github.com/NixOS/nixpkgs/commit/ac7b1aaed0
  typescript-language-server = super.typescript-language-server.overrideAttrs (old: {
    pnpmDeps = old.pnpmDeps.overrideAttrs {
      outputHash = "sha256-xR/EF60lVBsITKgH7wCM2wHM46PFQevD51KfCENSUH4=";
    };
  });
}

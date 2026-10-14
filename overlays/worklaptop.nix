(
  self: super:
  let
    optimizedForWorkLaptop =
      pkg:
      pkg.overrideAttrs (oldAttrs: {
        env = (oldAttrs.env or { }) // {
          NIX_CFLAGS_COMPILE = (oldAttrs.env.NIX_CFLAGS_COMPILE or "") + " -O2 -mcpu=apple-m4";
          NIX_CXXFLAGS_COMPILE = (oldAttrs.env.NIX_CFLAGS_COMPILE or "") + " -O2 -mcpu=apple-m4";
        };
      });
  in
  {

    qemu = optimizedForWorkLaptop (
      super.qemu.override ({
        hostCpuTargets = [
          "aarch64-softmmu"
        ];
      })
    );

    docker = optimizedForWorkLaptop super.docker;
    colima = optimizedForWorkLaptop super.colima;

    # typescript-language-server 6.0.2 landed in nixpkgs with a stale pnpmDeps
    # hash (pulled in by nvf's typescript language support). The pnpm deps hash
    # differs per platform, and the upstream fix
    # (https://github.com/NixOS/nixpkgs/commit/ac7b1aaed0) only corrected the
    # x86_64-linux one. Drop once nixpkgs ships a typescript-language-server
    # whose pnpmDeps builds on aarch64-darwin without this override.
    # Tracking: https://github.com/NixOS/nixpkgs/issues/573730
    typescript-language-server = super.typescript-language-server.overrideAttrs (old: {
      pnpmDeps = old.pnpmDeps.overrideAttrs {
        outputHash = "sha256-PmyJb8090pEPc09Tbv8RgdvQpzpba2L8ve87+aVncQU=";
      };
    });

  }
)

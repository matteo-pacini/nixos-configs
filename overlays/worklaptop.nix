(
  self: super:
  let
    optimizedForWorkLaptop =
      pkg:
      pkg.overrideAttrs (oldAttrs: {
        env = (oldAttrs.env or { }) // {
          NIX_CFLAGS_COMPILE = (oldAttrs.env.NIX_CFLAGS_COMPILE or "") + " -O2 -mcpu=apple-m1";
          NIX_CXXFLAGS_COMPILE = (oldAttrs.env.NIX_CFLAGS_COMPILE or "") + " -O2 -mcpu=apple-m1";
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

    # https://github.com/NixOS/nixpkgs/pull/449689
    gtk3 = super.gtk3.overrideAttrs (oldAttrs: {
      patches = (oldAttrs.patches or [ ]) ++ [ ../patches/gtk3-tests-sincos.patch ];
    });

  }
)

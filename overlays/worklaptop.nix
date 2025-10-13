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

    firefox = super.firefox.overrideAttrs (oldAttrs: {
      version = "143.0.3";
      src = super.fetchurl {
        url = "mirror://mozilla/firefox/releases/143.0.3/source/firefox-143.0.3.source.tar.xz";
        sha512 = "c092bd3aac79f856a804c908b76d40409ce052b00176269ea3029b5a3a6885d4d21ce26bd76c9ea13827ff75459b6b4b0566f5aa49035ac234ae5890c67845b0";
      };
    });

  }
)

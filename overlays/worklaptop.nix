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

    fish = super.fish.overrideAttrs (oldAttrs: {
      doCheck = false;
    });

    # TODO: Remove when https://github.com/NixOS/nixpkgs/pull/493943 lands
    yt-dlp = super.yt-dlp.overridePythonAttrs (o: {
      dependencies = builtins.filter (
        p:
        !(builtins.elem p.pname [
          "cffi"
          "secretstorage"
        ])
      ) o.dependencies;
    });

  }
)

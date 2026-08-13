{ inputs }:
(
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
    reshade-steam-proton = super.callPackage ../packages/reshade-steam-proton.nix { };
    optiscaler-client = super.callPackage ../packages/optiscaler-client.nix { };
    exiled-exchange-2 = super.callPackage ../packages/exiled-exchange-2.nix { };
    path-of-building-poe2 = super.callPackage ../packages/path-of-building-poe2.nix { };

    # Sourced from the linuwux-runtime flake input (flake = false, so it is a
    # bare source tree). Upstream tags no releases, hence the date-derived
    # unstable version — it is also what lands in -DLINUWUX_VERSION.
    linuwux-runtime = super.callPackage ../packages/linuwux-runtime.nix {
      src = inputs.linuwux-runtime;
      version = "0-unstable-${super.lib.concatStringsSep "-" (builtins.match "(....)(..)(..).*" inputs.linuwux-runtime.lastModifiedDate)}";
    };

    # MangoHud renders exec= output with font_secondary (font_size * 0.55 by
    # default) and paints the whole string in text_color, so the gamepad battery
    # line is half the height of the CPU/GPU rows and has no coloured label.
    # font_size_secondary= would fix the height, but that font is shared, so it
    # also enlarges every other secondary element (gamemode, resolution,
    # engine_version…) and can overlap columns (MangoHud#1913), and it still
    # cannot colour the label. The patch adds a separate exec2= that renders in
    # the primary font and splits on the first space, label in engine_color and
    # value in text_color, exactly like the built-in fields.
    mangohud = super.mangohud.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        ../patches/mangohud/001-exec2-styled-like-builtin-fields.patch
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
  }
)

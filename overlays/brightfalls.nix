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

    # ananicy-cpp 1.2.0 reaches std::memset and the <cstdint> integer aliases
    # through fmt rather than including those headers itself, and fmt 12.2.0
    # swapped <cstring>/<cstdint> in fmt/format.h for <string.h> — which only
    # declares memset in the global namespace. Breaks the build on any rev
    # carrying fmt >= 12.2.0. Pulled in by services.ananicy on this host
    # (hosts/BrightFalls/gaming.nix). See the patch header for the full
    # write-up, including why the glibc 2.42 attribution in both PRs below is
    # a red herring (glibc and clang are identical either side of the break).
    #
    # Upstream fix — the patch is the verbatim MR diff, so this override becomes
    # redundant the moment the nixpkgs one reaches the nixos-unstable channel:
    #   nixpkgs: https://github.com/NixOS/nixpkgs/pull/552211 (MERGED 2026-08-16
    #     as 74c1eb32, still 4 commits ahead of the e5bdc4a pin as of 2026-08-17)
    #   upstream: https://gitlab.com/ananicy-cpp/ananicy-cpp/-/merge_requests/43
    #
    # To drop this: once nixos-unstable carries #552211, delete this attribute
    # and patches/ananicy-cpp/. Inspect the effective patch list with
    #   nix eval .#nixosConfigurations.BrightFalls.pkgs.ananicy-cpp.patches
    # which prints nixpkgs' own patches alongside ours. #552211 fetchpatches the
    # very same MR diff, so once it lands ours is byte-identical to a patch
    # already applied and the build fails with a reversed/already-applied hunk —
    # that failure is the signal it is time to go, not a new bug.
    ananicy-cpp = super.ananicy-cpp.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        ../patches/ananicy-cpp/001-missing-cstring-cstdint-includes.patch
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

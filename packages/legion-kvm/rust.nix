# glibc-linked workspace binaries. The guest programs among them run against
# the Debian guest userspace (guest.nix), not this glibc, so guest.nix rejects
# any that reference a symbol version newer than Debian's glibc.
#
# The lock files are copies of upstream's (Cargo.lock and
# backends/nvidia/Cargo.lock) so evaluation doesn't need the fetched source.
{
  lib,
  rustPlatform,
  pkgsStatic,
  pkg-config,
  SDL2,
  libxkbcommon,
  alsa-lib,
  legionSource,
  resolution,
  memoryMiB,
  fullscreen,
  pinVcpus,
}:
{
  workspace = rustPlatform.buildRustPackage {
    pname = "legion-kvm-workspace";
    inherit (legionSource) version src;
    cargoLock.lockFile = ./Cargo.lock;
    nativeBuildInputs = [ pkg-config ];
    buildInputs = [
      SDL2
      libxkbcommon
      alsa-lib
    ];
    cargoBuildFlags = [ "--workspace" ];
    doCheck = false;
    # Guest-side keyboard, mouse and cursor for the AMD path. The launcher
    # built here is unused (static's is installed), so the launcher patches stay
    # there and changing them doesn't rebuild the guest.
    patches = [
      ./patches/legion-005-guest-input-permissions.patch
      ./patches/legion-006-kms-evdev-input.patch
      ./patches/legion-008-kms-cursor-plane.patch
    ];
    # cpu-adapter is a cdylib; buildRustPackage only installs binaries.
    postInstall = ''
      install -Dm0755 target/*/release/liblegion_cpu_adapter.so $out/lib/liblegion_cpu_adapter.so
    '';
  };

  vhost-user-nvgpu = rustPlatform.buildRustPackage {
    pname = "legion-kvm-vhost-user-nvgpu";
    inherit (legionSource) version src;
    sourceRoot = "source/backends/nvidia";
    cargoLock.lockFile = ./nvidia-Cargo.lock;
    cargoBuildFlags = [
      "-p"
      "device"
      "--features"
      "vhost-user"
      "--bin"
      "vhost-user-nvgpu"
    ];
    doCheck = false;
  };

  # Static musl builds, as upstream makes them: the guest init runs before any
  # guest userspace exists. Launcher-only changes go here, so they don't
  # rebuild the guest.
  static = pkgsStatic.rustPlatform.buildRustPackage {
    pname = "legion-kvm-static";
    inherit (legionSource) version src;
    cargoLock.lockFile = ./Cargo.lock;
    cargoBuildFlags = [
      "-p"
      "legion-kvm"
      "-p"
      "legion-guest-probe"
    ];
    doCheck = false;
    patches = [
      ./patches/legion-001-writable-session-copies.patch
      # The desktop scanout path (games, graphics-benchmark) imports guest
      # frames as GL_TEXTURE_EXTERNAL_OES, which Mesa supports only in GLES
      # contexts; with gl=on QEMU's window context is desktop GL and the window
      # stays black ("Bad t->Target in _mesa_test_texobj_completeness").
      # QEMU's own blit shaders are GLSL ES 3.00 either way.
      ./patches/legion-002-sdl-gles-display.patch
    ]
    ++ lib.optional pinVcpus ./patches/legion-003-vcpu-affinity-env.patch
    ++ [
      ./patches/legion-004-virtio-input-devices.patch
      ./patches/legion-007-qemu-parent-death-signal.patch
    ];
    # Upstream hardcodes the AMD path's guest display mode (virtio-gpu xres and
    # yres) for games at 1920x1080, with no setting for it. The memory and
    # fullscreen substitutions only change defaults: LEGION_MEMORY_MIB and
    # LEGION_FULLSCREEN still override them.
    postPatch = ''
      substituteInPlace src/game.rs \
        --replace-fail \
          '"client":"external","application":true,"width":1920,"height":1080,' \
          '"client":"external","application":true,"width":${toString resolution.width},"height":${toString resolution.height},' \
        --replace-fail \
          '.unwrap_or_else(|_| "12288".into())' \
          '.unwrap_or_else(|_| "${toString memoryMiB}".into())'
      substituteInPlace src/main.rs --replace-fail \
        'the default is 12288.' 'the default is ${toString memoryMiB}.'
    ''
    + lib.optionalString fullscreen ''
      substituteInPlace src/game.rs --replace-fail \
        'std::env::var("LEGION_FULLSCREEN").is_ok_and(|value|value=="1")' \
        'std::env::var("LEGION_FULLSCREEN").map_or(true, |value| value == "1")'
    '';
  };
}

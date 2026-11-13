# glibc-linked workspace binaries. The guest programs among them run against
# the Debian guest userspace (guest.nix), not this glibc, so guest.nix rejects
# any that reference a symbol version newer than Debian's glibc.
{
  rustPlatform,
  pkgsStatic,
  pkg-config,
  SDL2,
  libxkbcommon,
  alsa-lib,
  legionSource,
  resolution,
}:
{
  workspace = rustPlatform.buildRustPackage {
    pname = "legion-kvm-workspace";
    inherit (legionSource) version src;
    cargoLock.lockFile = "${legionSource.src}/Cargo.lock";
    nativeBuildInputs = [ pkg-config ];
    buildInputs = [
      SDL2
      libxkbcommon
      alsa-lib
    ];
    cargoBuildFlags = [ "--workspace" ];
    doCheck = false;
    # cpu-adapter is a cdylib; buildRustPackage only installs binaries.
    postInstall = ''
      install -Dm0755 target/*/release/liblegion_cpu_adapter.so $out/lib/liblegion_cpu_adapter.so
    '';
  };

  vhost-user-nvgpu = rustPlatform.buildRustPackage {
    pname = "legion-kvm-vhost-user-nvgpu";
    inherit (legionSource) version src;
    sourceRoot = "source/backends/nvidia";
    cargoLock.lockFile = "${legionSource.src}/backends/nvidia/Cargo.lock";
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
  # guest userspace exists.
  static = pkgsStatic.rustPlatform.buildRustPackage {
    pname = "legion-kvm-static";
    inherit (legionSource) version src;
    cargoLock.lockFile = "${legionSource.src}/Cargo.lock";
    cargoBuildFlags = [
      "-p"
      "legion-kvm"
      "-p"
      "legion-guest-probe"
    ];
    doCheck = false;
    # Upstream hardcodes the AMD path's guest display mode (virtio-gpu xres and
    # yres) for games at 1920x1080, with no setting for it.
    postPatch = ''
      substituteInPlace src/game.rs --replace-fail \
        '"client":"external","application":true,"width":1920,"height":1080,' \
        '"client":"external","application":true,"width":${toString resolution.width},"height":${toString resolution.height},'
    '';
  };
}

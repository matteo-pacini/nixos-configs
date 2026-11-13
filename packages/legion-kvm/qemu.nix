# QEMU with upstream's runtime patch and configure flags (build_runtime.py
# qemu()). nixpkgs' qemu.src is the same 11.1.2 release upstream pins.
{
  stdenv,
  qemu,
  python3Packages,
  meson,
  ninja,
  pkg-config,
  flex,
  bison,
  glib,
  pixman,
  dtc,
  libpulseaudio,
  libepoxy,
  libgbm,
  libdrm,
  SDL2,
  virglrenderer,
  zlib,
  legionSource,
}:
assert qemu.version == "11.1.2";
stdenv.mkDerivation {
  pname = "legion-kvm-qemu";
  inherit (qemu) version src;
  patches = [ "${legionSource.src}/patches/qemu-runtime.patch" ];
  nativeBuildInputs = [
    python3Packages.python
    python3Packages.distlib
    python3Packages.setuptools
    python3Packages.wheel
    python3Packages.pycotap
    python3Packages.qemu-qmp
    meson
    ninja
    pkg-config
    flex
    bison
  ];
  buildInputs = [
    glib
    pixman
    dtc
    libpulseaudio
    libepoxy
    libgbm
    libdrm
    SDL2
    virglrenderer
    zlib
  ];
  dontUseMesonConfigure = true;
  dontUseNinjaBuild = true;
  dontUseNinjaInstall = true;
  configurePhase = ''
    runHook preConfigure
    patchShebangs .
    mkdir build && cd build
    ../configure --target-list=x86_64-softmmu --without-default-features \
      --enable-kvm --enable-vhost-user --disable-tcg --disable-rust \
      --disable-tools --disable-guest-agent --disable-docs --disable-werror \
      --enable-pa --audio-drv-list=pa --enable-opengl --enable-virglrenderer \
      --enable-sdl --enable-pixman --disable-download
    runHook postConfigure
  '';
  buildPhase = ''
    runHook preBuild
    ninja -j$NIX_BUILD_CORES qemu-system-x86_64
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    install -Dm0755 qemu-system-x86_64 $out/bin/qemu-system-x86_64
    for name in bios-256k.bin linuxboot_dma.bin kvmvapic.bin multiboot_dma.bin pvh.bin; do
      install -Dm0644 ../pc-bios/$name $out/share/qemu/$name
    done
    runHook postInstall
  '';
}

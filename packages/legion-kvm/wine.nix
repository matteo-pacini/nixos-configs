# Patched Wine ntdll.dll (build_runtime.py wine()); guest.nix encodes it as the
# repair recipe against GE-Proton11-11.
# Upstream builds the PE side with clang/lld and no mingw; this does the same.
{
  stdenv,
  fetchurl,
  python3,
  flex,
  bison,
  perl,
  autoconf,
  automake,
  libtool,
  llvmPackages,
  legionSource,
  proton,
}:
stdenv.mkDerivation {
  pname = "legion-kvm-wine-ntdll";
  version = "c53678ab";
  # Hash from upstream's config/sources.json.
  src = fetchurl {
    name = "wine-c53678ab.tar.gz";
    url = "https://codeload.github.com/ValveSoftware/wine/tar.gz/c53678ab22a85f0fad3588dd34f0452a463bd015";
    sha256 = "a156c7e69af23fc89b6b75b655ab6bc2879ec3caa052de36b0162420d8d25e0c";
  };
  patches = [ "${legionSource.src}/patches/wine-runtime.patch" ];
  nativeBuildInputs = [
    python3
    flex
    bison
    perl
    autoconf
    automake
    libtool
    llvmPackages.clang-unwrapped
    llvmPackages.lld
    llvmPackages.llvm
  ];
  hardeningDisable = [ "all" ];
  dontConfigure = true;
  buildPhase = ''
    runHook preBuild
    patchShebangs .
    export HOME=$TMPDIR
    [ -x configure ] || ./autogen.sh
    mkdir build && cd build
    ../configure --enable-win64 --disable-tests --without-x --without-wayland \
      --without-vulkan --without-opengl --without-gstreamer --without-alsa \
      --without-pulse --without-dbus --without-cups --without-udev --without-freetype
    make -j$NIX_BUILD_CORES dlls/ntdll/x86_64-windows/ntdll.dll
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    proton=${proton.src}
    python3 - $proton <<'PY'
    import hashlib, json, sys
    from pathlib import Path
    proton = Path(sys.argv[1])
    expected = json.loads(Path('${legionSource.src}/config/compatibility.json').read_text())
    for key, relative in [('source_sha256', 'files/lib/wine/x86_64-windows/ntdll.dll'),
                          ('unix_sha256', 'files/lib/wine/x86_64-unix/ntdll.so')]:
        if hashlib.sha256((proton/relative).read_bytes()).hexdigest() != expected[key]:
            sys.exit('Proton does not match config/compatibility.json: ' + relative)
    PY
    install -Dm0644 dlls/ntdll/x86_64-windows/ntdll.dll $out/ntdll.dll
    runHook postInstall
  '';
}

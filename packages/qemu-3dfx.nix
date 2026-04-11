{
  lib,
  stdenv,
  fetchurl,
  fetchFromGitHub,
  fetchpatch,
  # Build tools
  python3Packages,
  pkg-config,
  flex,
  bison,
  meson,
  ninja,
  perl,
  makeWrapper,
  removeReferencesTo,
  buildPackages,
  # Core libs
  glib,
  gnutls,
  zlib,
  pixman,
  vde2,
  lzo,
  snappy,
  libtasn1,
  libslirp,
  curl,
  dtc,
  ncurses,
  # Display / Graphics
  SDL2,
  SDL2_image,
  libjpeg,
  libpng,
  libGL,
  mesa,
  libx11,
  libxxf86vm,
  # Darwin
  darwin ? { },
  # Linux
  libcap ? null,
  libcap_ng ? null,
  attr ? null,
  libaio ? null,
  libseccomp ? null,
  # Guest wrappers (mingw cross-compilation)
  pkgsCross,
  gendef,
  tinyxxd,
}:

let
  qemu3dfxRev = "8c35ed82d6ca6907a4b0bcc27c23785ad10562c4";
  qemu3dfxShortRev = builtins.substring 0 7 qemu3dfxRev;

  qemu3dfxSrc = fetchFromGitHub {
    owner = "kjliew";
    repo = "qemu-3dfx";
    rev = qemu3dfxRev;
    hash = "sha256-iZiyED+JyVRvvtWmlQGglwmVhbiBruHvblZ3/fLjjsk=";
  };

  # Override gendef to build on Darwin (upstream restricts to Linux)
  gendef' = gendef.overrideAttrs (old: {
    meta = old.meta // {
      platforms = lib.platforms.unix;
    };
  });

  mingwGcc = pkgsCross.mingw32.buildPackages.gcc;
  mingwBintools = pkgsCross.mingw32.buildPackages.binutils;
  mingwPrefix = "i686-w64-mingw32-";
  mcfgthreads = pkgsCross.mingw32.windows.mcfgthreads;
in

stdenv.mkDerivation (finalAttrs: {
  pname = "qemu-3dfx";
  version = "9.2.2";

  src = fetchurl {
    url = "https://download.qemu.org/qemu-${finalAttrs.version}.tar.xz";
    hash = "sha256-dS6u63cpI6c9U2sjHgW8wJybH1FpCkGtmXPZAOTsn78=";
  };

  patches = [
    # Nested virtualisation fix (from nixpkgs 9.2.2)
    (fetchpatch {
      url = "https://gitlab.com/qemu-project/qemu/-/commit/3e4546d5bd38a1e98d4bd2de48631abf0398a3a2.diff";
      sha256 = "sha256-oC+bRjEHixv1QEFO9XAm4HHOwoiT+NkhknKGPydnZ5E=";
      revert = true;
    })

    # 3Dfx Glide / Mesa passthrough (pinned to qemu-3dfx rev)
    ./qemu-3dfx-mesa-glide.patch
  ];

  postPatch = ''
    # --- Copy 3dfx overlay files into QEMU source tree ---
    cp -r ${qemu3dfxSrc}/qemu-0/hw/3dfx hw/3dfx
    cp -r ${qemu3dfxSrc}/qemu-1/hw/mesa hw/mesa
    chmod -R u+w hw/3dfx hw/mesa

    # --- Replicate scripts/sign_commit ---
    # 1. Inject git rev into source files
    sed -i "s/\(rev_\[\).*\].*/\1\] = \"${qemu3dfxShortRev}-\"/" \
      hw/3dfx/g2xfuncs.h hw/mesa/mglfuncs.h $(find . -maxdepth 2 -name vl.c)

    # 2. Replace HASH_ALGO if present (QEMU 9.2.x already uses the correct constant)
    CRYP=$(grep HASH_ALG qapi/crypto.json | sed "s/.*:\ //;s/.*\(HASH_[A-Z]*\).*/\1/" || true)
    if [ -n "$CRYP" ]; then
      sed -i "s/HASH_ALGO/$CRYP/" hw/mesa/mesagl_pfn.h
    fi

    # 3. Fix include paths (overlay targets newer QEMU where sysemu/ was renamed to system/)
    #    QEMU 9.2.x still uses sysemu/ for kvm.h and whpx.h, and exec/ for address-spaces.h
    sed -i 's|"system/kvm.h"|"sysemu/kvm.h"|' \
      $(grep -rl '"system/kvm.h"' hw/3dfx hw/mesa) 2>/dev/null || true
    sed -i 's|"system/whpx.h"|"sysemu/whpx.h"|' \
      $(grep -rl '"system/whpx.h"' hw/3dfx hw/mesa) 2>/dev/null || true
    sed -i 's|"system/address-spaces.h"|"exec/address-spaces.h"|' \
      $(grep -rl '"system/address-spaces.h"' hw/3dfx hw/mesa) 2>/dev/null || true

    # 4. Read module variable name from target/i386/meson.build and patch
    MODS=$(tail -n 2 target/i386/meson.build | head -n 1 | sed "s/.*:\ //;s/\}//" | tr -d '[:space:]')
    if [ -n "$MODS" ]; then
      sed -i "s/i386.*_ss/$MODS/" hw/3dfx/meson.build hw/mesa/meson.build
    fi

    # 5. Check klass signature for API compatibility
    if expr "$(grep 'base_init)' include/qom/object.h)" : ".*\*klass,\ void\ " >/dev/null 2>&1; then
      sed -i -e "s/\*klass,\ const\ void/\*klass,\ void/;s/\"system\(\/address\-\)/\"exec\1/" \
        $(grep -rl '\*klass,\ const\ void' hw/3dfx hw/mesa) 2>/dev/null || true
    fi

    # --- Standard nixpkgs QEMU patches ---
    # Remove /var/run mkdir from guest agent build
    sed -i "/install_emptydir(get_option('localstatedir') \/ 'run')/d" \
      qga/meson.build

    # --- Darwin fixes ---
  ''
  + lib.optionalString stdenv.hostPlatform.isDarwin ''
    # Remove hardcoded XQuartz paths - Nix provides X11 via buildInputs
    substituteInPlace meson.build \
      --replace-fail "c_args += ['-I/opt/X11/include']" "" \
      --replace-fail "'-L/opt/X11/lib', " ""

    # Use SDL GL context instead of X11/Linux context on Darwin
    substituteInPlace hw/mesa/meson.build \
      --replace-fail "'mglcntx_linux.c'," "'mglcntx_sdlgl.c',"

    # Define missing GL extension constants for Darwin/Mesa
    sed -i '1i\
    #ifndef GL_TEXTURE_RECTANGLE_NV\
    #define GL_TEXTURE_RECTANGLE_NV 0x84F5\
    #endif\
    #ifndef GL_TEXTURE_BINDING_RECTANGLE_NV\
    #define GL_TEXTURE_BINDING_RECTANGLE_NV 0x84F6\
    #endif' hw/mesa/mglcntx_sdlgl.c

    # Remove Rez/SetFile commands from entitlement script (not available in sandbox)
    substituteInPlace scripts/entitlement.sh \
      --replace-fail 'Rez -append "$ICON" -o "$SRC"' "" \
      --replace-fail 'SetFile -a C "$SRC"' ""
  '';

  preConfigure = ''
    unset CPP
    chmod +x ./scripts/shaderinclude.py
    patchShebangs .
    # Avoid conflicts with libc++ include for <version>
    mv VERSION QEMU_VERSION
    substituteInPlace configure \
      --replace-warn '$source_path/VERSION' '$source_path/QEMU_VERSION'
    substituteInPlace meson.build \
      --replace-warn "'VERSION'" "'QEMU_VERSION'"
    substituteInPlace python/qemu/machine/machine.py \
      --replace-fail /var/tmp "$TMPDIR"
  '';

  dontUseMesonConfigure = true;
  dontAddStaticConfigureFlags = true;

  configureFlags = [
    "--disable-strip"
    "--enable-gnutls"
    "--localstatedir=/var"
    "--sysconfdir=/etc"
    "--cross-prefix=${stdenv.cc.targetPrefix}"
    "--target-list=i386-softmmu,x86_64-softmmu"
    "--enable-sdl"
    "--enable-vnc"
    "--enable-tpm"
    "--disable-docs"
    "--disable-guest-agent"
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    "--enable-cocoa"
    "--enable-hvf"
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    "--enable-linux-aio"
    "--enable-kvm"
  ];

  depsBuildBuild = [ buildPackages.stdenv.cc ];

  nativeBuildInputs = [
    makeWrapper
    removeReferencesTo
    pkg-config
    flex
    bison
    meson
    ninja
    perl
    python3Packages.distlib
    python3Packages.python
    dtc
    # Guest wrappers cross-compilation
    mingwGcc
    mingwBintools
    gendef'
    tinyxxd
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [ darwin.sigtool ];

  buildInputs = [
    glib
    gnutls
    zlib
    dtc
    pixman
    vde2
    lzo
    snappy
    libtasn1
    libslirp
    curl
    ncurses
    # Display (SDL required for 3dfx passthrough)
    SDL2
    SDL2_image
    # VNC
    libjpeg
    libpng
    # OpenGL / X11 (needed for 3dfx host-side rendering)
    libGL
    libx11
    libxxf86vm
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [ mesa.dev ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    libcap_ng
    libcap
    attr
    libaio
  ];

  preBuild = "cd build";

  # QEMU uses codesign entitlements on Darwin; stripping voids them
  dontStrip = stdenv.hostPlatform.isDarwin;

  postFixup = ''
    rm -f $out/share/applications/qemu.desktop
  '' + lib.optionalString stdenv.hostPlatform.isDarwin ''
    # The 3dfx passthrough links mesa's libGL on Darwin (not done in upstream QEMU).
    # Mesa's libGL uses @rpath/libgallium, so add the rpath and re-codesign.
    for f in $out/bin/qemu-system-*; do
      install_name_tool -add_rpath "${lib.getLib mesa}/lib" "$f" || true
      codesign --force --sign - "$f"
    done
  '';

  postInstall = ''
    # --- Build guest wrappers (Windows DLLs via mingw cross-compilation) ---
    wrapperBuildDir=$(mktemp -d)
    cp -r ${qemu3dfxSrc}/* $wrapperBuildDir/
    chmod -R u+w $wrapperBuildDir
    cd $wrapperBuildDir/wrappers/3dfx

    mkdir -p build
    cd build

    # Generate Makefile from template (replicating conf_wrapper for cross-build)
    cat ../src/Makefile.in > Makefile

    # Set cross-compiler prefix
    sed -i "s|^\(CROSS=\).*|\1${mingwPrefix}|" Makefile

    # Prefix RC, STRIP, DLLTOOL with CROSS for cross-build
    sed -i -e "s/^\(RC=\)/\1\$(CROSS)/" Makefile
    sed -i -e "s/^\(STRIP=\)/\1\$(CROSS)/" Makefile
    sed -i -e "s/^\(DLLTOOL=\)/\1\$(CROSS)/" Makefile

    # Remove wglinfo tool target (host-only)
    sed -i -e "s/^\(TOOLS=\)wglinfo.exe.*/\1/" Makefile

    # Remove MSYSTEM check (only valid in MSYS2)
    sed -i '/.*MSYSTEM.*!=.*MINGW32.*/d' Makefile

    # Remove DJGPP/DOS32 and driver installer targets (not needed/available)
    sed -i '/.*make.*-C.*dxe/d' Makefile
    sed -i '/.*make.*-C.*ovl/d' Makefile
    sed -i '/.*make.*-C.*drv/d' Makefile

    # Hardcode git rev (no .git in Nix build)
    sed -i "s|^GIT=.*|GIT=${qemu3dfxShortRev}-|" Makefile

    # Fix CFLAGS for i686 target (upstream uses x86-64-v2 which is invalid for 32-bit)
    sed -i 's/-march=x86-64-v2/-march=i686 -msse2/' Makefile

    # Provide cross-compiled libraries the GCC wrapper expects
    # mcfgthreads: thread implementation for mingw
    # libintl: empty stub - the DLLs don't use gettext, but the GCC wrapper links it
    ${mingwBintools}/bin/${mingwPrefix}ar rcs libintl.a
    sed -i "s|^LDFLAGS=-static-libgcc|LDFLAGS=-static-libgcc -L${mcfgthreads}/lib -L.|" Makefile

    # Fix exports-check to use cross-objdump (host objdump can't read PE)
    sed -i "s|objdump|\$(CROSS)objdump|g" Makefile

    # Build wrappers (sequential to avoid fxlib race condition)
    make -j1 GENDEF=gendef

    # Install guest wrappers
    mkdir -p $out/share/qemu-3dfx/wrappers
    cp -v *.dll $out/share/qemu-3dfx/wrappers/ 2>/dev/null || true
    cp -v *.dll.a $out/share/qemu-3dfx/wrappers/ 2>/dev/null || true
    cp -v *.def $out/share/qemu-3dfx/wrappers/ 2>/dev/null || true

    cd /
    rm -rf $wrapperBuildDir
  '';

  # Builds in ~3h with 2 cores, ~20m with big-parallel
  requiredSystemFeatures = [ "big-parallel" ];

  meta = {
    description = "QEMU with 3Dfx Glide and Mesa/OpenGL passthrough for retro gaming";
    homepage = "https://github.com/kjliew/qemu-3dfx";
    license = lib.licenses.gpl2Plus;
    platforms = lib.platforms.unix;
    mainProgram = "qemu-system-x86_64";
  };
})

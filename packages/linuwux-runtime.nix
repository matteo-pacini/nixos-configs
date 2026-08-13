{
  lib,
  stdenv,
  src,
  version,
}:

stdenv.mkDerivation {

  pname = "linuwux-runtime";
  inherit version src;

  # Upstream ships no build system: a single translation unit compiled straight
  # into a preload shim. This mirrors its build script's compile line.
  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    $CC -std=gnu11 -O2 -fPIC -shared -Wall \
      -DLINUWUX_VERSION='"${version}"' \
      -o liblinuwux.so src/linuwux.c -ldl

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -Dm444 liblinuwux.so $out/lib/liblinuwux.so

    runHook postInstall
  '';

  meta = {
    description = "LD_PRELOAD runtime shim built from src/linuwux.c";
    homepage = "https://github.com/brcly/linuwux-runtime";
    platforms = [ "x86_64-linux" ];
    # license intentionally unset: upstream declares none that was verified.
  };
}

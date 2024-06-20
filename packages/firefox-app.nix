{
  stdenvNoCC,
  lib,
  fetchurl,
  undmg,
}:
stdenvNoCC.mkDerivation rec {
  pname = "Firefox";
  version = "127.0.1";

  buildInputs = [ undmg ];

  sourceRoot = ".";

  src = fetchurl {
    name = "Firefox-${version}.dmg";
    url = "https://download-installer.cdn.mozilla.net/pub/firefox/releases/${version}/mac/en-GB/Firefox%20${version}.dmg";
    hash = "sha256-ygCyM0viFpqY8Rjn2dV8r8mNOYDVZ6BKO2LjV5Qc6tw=";
  };

  doNotPatch = true;
  doNotBuild = true;
  doNotConfigure = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/Applications
    cp -r Firefox*.app "$out/Applications/"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Mozilla Firefox web browser for macOS";
    homepage = "https://www.mozilla.org/en-US/firefox/";
    platforms = platforms.darwin;
    license = lib.licenses.mpl20;
    mainProgram = "firefox";
  };
}

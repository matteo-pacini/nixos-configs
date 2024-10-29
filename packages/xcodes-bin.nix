{
  stdenvNoCC,
  fetchzip,
  lib,
}:

stdenvNoCC.mkDerivation rec {

  pname = "xcodes-bin";
  version = "1.5.0";

  src = fetchzip {
    url = "https://github.com/XcodesOrg/xcodes/releases/download/${version}/xcodes-${version}.arm64_mojave.bottle.tar.gz";
    hash = "sha256-CKmEMMhUzfhZ+HPmiia0Qob6FEjuXkbzWjohI8tyDQA=";
  };

  dontPatch = true;
  dontConfigure = true;
  dontBuild = true;

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src/${version}/bin/xcodes" $out/bin/xcodes
    runHook postInstall
  '';

  meta = with lib; {
    platforms = platforms.darwin;
  };
}

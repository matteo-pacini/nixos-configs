{
  stdenvNoCC,
  fetchurl,
  undmg,
}:
stdenvNoCC.mkDerivation rec {
  pname = "Firefox";
  version = "126.0";

  buildInputs = [undmg];

  sourceRoot = ".";

  src = fetchurl {
    name = "Firefox-${version}.dmg";
    url = "https://download-installer.cdn.mozilla.net/pub/firefox/releases/${version}/mac/en-GB/Firefox%20${version}.dmg";
    hash = "sha256-0fSvHy9vwCbbhZ1ikdw7ZfxpkHdyfSdwoT+uDyE8p0I=";
  };

  phases = ["unpackPhase" "installPhase"];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/Applications
    cp -r Firefox*.app "$out/Applications/"

    runHook postInstall
  '';
}

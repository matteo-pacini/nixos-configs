{
  stdenvNoCC,
  fetchurl,
  undmg,
}:
stdenvNoCC.mkDerivation rec {
  pname = "Firefox";
  version = "125.0.3";

  buildInputs = [undmg];

  sourceRoot = ".";

  src = fetchurl {
    name = "Firefox-${version}.dmg";
    url = "https://download-installer.cdn.mozilla.net/pub/firefox/releases/${version}/mac/en-GB/Firefox%20${version}.dmg";
    hash = "sha256-Yl4wvtzpNsViCHMW9mTvBDM36HGX8o57p/lx8198f1E=";
  };

  phases = ["unpackPhase" "installPhase"];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/Applications
    cp -r Firefox*.app "$out/Applications/"

    runHook postInstall
  '';
}

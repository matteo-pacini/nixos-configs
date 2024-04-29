{
  fetchurl,
  lib,
  stdenvNoCC,
  unzip,
}:
stdenvNoCC.mkDerivation rec {
  pname = "xcodes-app-bin";
  version = "2.1.2b26";

  src = fetchurl {
    url = "https://github.com/XcodesOrg/XcodesApp/releases/download/v${version}/Xcodes.zip";
    hash = "sha256-gEvIi4X2oGj4gNK4gGT+m4e8hAEoZvOF85BOllA6jGA=";
  };

  nativeBuildInputs = [unzip];

  dontPatch = true;
  dontConfigure = true;
  dontBuild = true;

  unpackPhase = ''
    runHook preUnpack
    unzip -q $src
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/Applications
    cp -r Xcodes.app $out/Applications/
    runHook postInstall
  '';

  meta = with lib; {
    description = "The easiest way to install and switch between multiple versions of Xcode - with a mouse click.";
    homepage = "https://github.com/XcodesOrg/XcodesApp";
    license = licenses.mit;
    maintainers = with maintainers; [];
    platforms = ["x86_64-darwin" "aarch64-darwin"];
  };
}

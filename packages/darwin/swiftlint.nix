{
  stdenvNoCC,
  lib,
  fetchurl,
  unzip,
}:
stdenvNoCC.mkDerivation rec {
  name = "SwiftLint";
  version = "0.55.1";

  src = fetchurl {
    url = "https://github.com/realm/SwiftLint/releases/download/${version}/portable_swiftlint.zip";
    hash = "sha256-Tmhw30CJaVQlcYnHjzmwrDpugHgR2/ihHIV8M+O2zwI=";
  };

  dontPatch = true;
  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [unzip];

  unpackPhase = ''
    runHook preUnpack
    unzip -q $src
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp swiftlint $out/bin
    runHook postInstall
  '';

  meta = with lib; {
    description = "A tool to enforce Swift style and conventions.";
    homepage = "https://realm.github.io/SwiftLint/";
    platforms = platforms.darwin;
    license = lib.licenses.mit;
  };
}

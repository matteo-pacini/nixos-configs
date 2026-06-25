{
  lib,
  stdenvNoCC,
  fetchzip,
  rsync,
  wineWow64Packages,
  writeShellScript,
}:

let
  version = "0.21.1";
  wine = "${wineWow64Packages.staging}/bin/wine";
  rsyncBin = "${rsync}/bin/rsync";

  launcher = writeShellScript "pob2" ''
    set -euo pipefail
    export WINEPREFIX="''${XDG_DATA_HOME:-$HOME/.local/share}/path-of-building-poe2/prefix"
    appdir="''${XDG_DATA_HOME:-$HOME/.local/share}/path-of-building-poe2/app"
    mkdir -p "$appdir" "$WINEPREFIX"
    # Store files are read-only; heal any prior copy and force the synced tree
    # writable so PoB can save Settings.xml / builds.
    chmod -R u+w "$appdir"
    ${rsyncBin} -a --delete --chmod=u+w \
      --exclude Builds --exclude Settings.xml --exclude imgui.ini \
      --exclude poe_api_response.json --exclude Update \
      "@shareDir@/" "$appdir/"
    cd "$appdir"
    exec ${wine} "Path of Building-PoE2.exe" "$@"
  '';
in

stdenvNoCC.mkDerivation {
  pname = "path-of-building-poe2";
  inherit version;

  src = fetchzip {
    url = "https://github.com/PathOfBuildingCommunity/PathOfBuilding-PoE2/releases/download/v${version}/PathOfBuildingCommunity-PoE2-Portable.zip";
    hash = "sha256-HTnjO60JEOTbt7xQzlnTX36hzghtYqgGjWxH8LkF61I=";
    stripRoot = false;
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    shareDir="$out/share/path-of-building-poe2"
    mkdir -p "$shareDir" "$out/bin"
    cp -r . "$shareDir/"
    substitute ${launcher} "$out/bin/pob2" \
      --replace-fail "@shareDir@" "$shareDir"
    chmod +x "$out/bin/pob2"
    runHook postInstall
  '';

  meta = {
    description = "Path of Building Community fork for Path of Exile 2, running under Wine";
    homepage = "https://github.com/PathOfBuildingCommunity/PathOfBuilding-PoE2";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "pob2";
  };
}

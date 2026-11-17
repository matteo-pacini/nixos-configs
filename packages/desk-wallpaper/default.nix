{
  lib,
  stdenv,
  swift,
}:

stdenv.mkDerivation {
  pname = "desk-wallpaper";
  version = "0.1.0";

  src = ./main.swift;
  dontUnpack = true;

  strictDeps = true;

  nativeBuildInputs = [ swift ];

  # One file, no dependencies: swiftc directly, as nixpkgs' vzvm does,
  # instead of swiftpm.
  buildPhase = ''
    runHook preBuild
    swiftc -O -o desk-wallpaper $src
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 desk-wallpaper $out/bin/desk-wallpaper
    runHook postInstall
  '';

  meta = {
    description = "Sets one desktop picture per named display on macOS";
    platforms = lib.platforms.darwin;
    mainProgram = "desk-wallpaper";
  };
}

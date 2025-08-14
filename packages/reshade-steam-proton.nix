{
  stdenv,
  fetchFromGitHub,
  makeWrapper,
  lib,
  wineWowPackages,
  p7zip,
  git,
  curl,
  wget,
  file,
}:
let
  binPath = lib.makeBinPath [
    wineWowPackages.minimal
    p7zip
    git
    curl
    wget
    file
  ];
in

stdenv.mkDerivation {

  pname = "reshade-steam-proton";
  version = "unstable-2023-04-22";

  src = fetchFromGitHub {
    owner = "kevinlekiller";
    repo = "reshade-steam-proton";
    rev = "55d4a681c9389e20ab569234f01bf67dbd6866a7";
    hash = "sha256-jVqeVIW5cIgRkK/V3HxN1RKcRb+LaFR7n8GHxvowW0I=";
  };

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin
    cp $src/*.sh $out/bin/
    wrapProgram "$out/bin/reshade-steam-proton.sh" \
      --prefix PATH : "${binPath}"
    wrapProgram "$out/bin/reshade-linux.sh" \
      --prefix PATH : "${binPath}"
    wrapProgram "$out/bin/reshade-linux-flatpak.sh" \
      --prefix PATH : "${binPath}"
  '';

  meta = {
    description = "Easy setup and updating of ReShade on Linux for games using wine or proton";
    homepage = "https://github.com/kevinlekiller/reshade-steam-proton";
    platforms = [ "x86_64-linux" ];
    license = lib.licenses.gpl2;
  };
}

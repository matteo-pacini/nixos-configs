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

stdenv.mkDerivation {

  pname = "reshade-steam-proton";
  version = "unstable-2023-04-22";

  src = fetchFromGitHub {
    owner = "kevinlekiller";
    repo = "reshade-steam-proton";
    rev = "55d4a681c9389e20ab569234f01bf67dbd6866a7";
    sha256 = "sha256-jVqeVIW5cIgRkK/V3HxN1RKcRb+LaFR7n8GHxvowW0I=";
  };

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin
    cp "$src/reshade-linux.sh" "$out/bin/._reshade-linux.sh"
    cp "$src/reshade-linux-flatpak.sh" "$out/bin/._reshade-linux-flatpak.sh"
    cp "$src/reshade-steam-proton.sh" "$out/bin/._reshade-steam-proton.sh"
    makeWrapper "$out/bin/._reshade-linux.sh" \
                "$out/bin/reshade-linux.sh" \
                 --prefix PATH : "${
                   lib.makeBinPath [
                     wineWowPackages.minimal
                     p7zip
                     git
                     curl
                     wget
                     file
                   ]
                 }"


    makeWrapper "$out/bin/._reshade-linux-flatpak.sh" \
                "$out/bin/reshade-linux-flatpak.sh" \
                 --prefix PATH : "${
                   lib.makeBinPath [
                     wineWowPackages.minimal
                     p7zip
                     git
                     curl
                     wget
                     file
                   ]
                 }"

  '';

  meta = with lib; {
    description = "Easy setup and updating of ReShade on Linux for games using wine or proton";
    homepage = "https://github.com/kevinlekiller/reshade-steam-proton";
    platforms = [ "x86_64-linux" ];
    license = licenses.gpl2;
  };
}

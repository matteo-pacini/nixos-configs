{
  stdenvNoCC,
  lib,
  fetchurl,
  git,
  makeWrapper,
}:
stdenvNoCC.mkDerivation rec {
  pname = "zed";
  version = "0.140.5";

  sourceRoot = ".";

  src = fetchurl {
    url = "https://github.com/zed-industries/zed/releases/download/v${version}/Zed.dmg";
    hash = "sha256-+D7SEywQtGML8405i4YUkl0Ir3RSgS0dledSvyLFYhk=";
  };

  nativeBuildInputs = [ makeWrapper ];

  unpackCmd = ''
    echo "Creating temp directory"
    mnt=$(TMPDIR=/tmp mktemp -d -t nix-XXXXXXXXXX)
    function finish {
      echo "Ejecting temp directory"
      /usr/bin/hdiutil detach $mnt -force
      rm -rf $mnt
    }
    # Detach volume when receiving SIG "0"
    trap finish EXIT
    # Mount DMG file
    echo "Mounting DMG file into \"$mnt\""
    /usr/bin/hdiutil attach -nobrowse -mountpoint $mnt $curSrc
    # Copy content to local dir for later use
    echo 'Copying extracted content into "sourceRoot"'
    cp -r $mnt/Zed.app $PWD/
  '';

  doNotPatch = true;
  doNotBuild = true;
  doNotConfigure = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/{bin,Applications}
    cp -r Zed.app $out/Applications/
    wrapProgram $out/Applications/Zed.app/Contents/MacOS/zed \
      --prefix PATH : ${lib.makeBinPath [ git ]}
    ln -s $out/Applications/Zed.app/Contents/MacOS/zed $out/bin/zed
    runHook postInstall
  '';

  meta = with lib; {
    description = "Code at the speed of thought";
    longDescription = ''
      Zed is a high-performance, multiplayer code editor from the creators of Atom and Tree-sitter. 
      It's also open source.
    '';
    homepage = "https://zed.dev/";
    platforms = platforms.darwin;
    license = with licenses; [
      agpl3Only
      asl20
      gpl3Only
    ];
    mainProgram = "zed";
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
}

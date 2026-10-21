{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
  jdk21_headless,
  writeShellScriptBin,
}:
let
  minecraftVersion = "1.21.1";
  neoforgeVersion = "21.1.256";
  jre = jdk21_headless;

  # NeoForge's installer downloads the vanilla server jar and its libraries
  # from Mojang/NeoForged maven and binpatches them. Its output is
  # byte-identical between runs, so it works as a fixed-output derivation
  # (network allowed, content pinned by outputHash). Re-run with a fake hash
  # on a NeoForge bump.
  neoforge = stdenvNoCC.mkDerivation {
    pname = "neoforge-server";
    version = neoforgeVersion;

    src = fetchurl {
      url = "https://maven.neoforged.net/releases/net/neoforged/neoforge/${neoforgeVersion}/neoforge-${neoforgeVersion}-installer.jar";
      hash = "sha256-Sq2THo/YX79ro1urZHgRBp01/wEJAEkuOdscuLAXNIw=";
    };
    dontUnpack = true;

    nativeBuildInputs = [ jre ];

    buildPhase = ''
      runHook preBuild
      mkdir -p $out
      cd $out
      java -jar $src --install-server .
      # Timestamped log and launcher scripts would break the fixed output.
      rm -f *.log run.sh run.bat user_jvm_args.txt
      runHook postBuild
    '';
    dontInstall = true;
    dontFixup = true;

    outputHashMode = "recursive";
    outputHash = "sha256-uwgLR+Fub84AXB9kOASeGigVtwiiTlAuQKh2YEsR0S8=";
  };

  # unix_args.txt references libraries/ relative to the working directory;
  # point it at the store so the data dir needs no copy of the libraries.
  argsFile = stdenvNoCC.mkDerivation {
    name = "neoforge-${neoforgeVersion}-unix-args.txt";
    dontUnpack = true;
    installPhase = ''
      sed -E 's#(^|[ =:,])libraries/#\1${neoforge}/libraries/#g; s#=libraries$#=${neoforge}/libraries#' \
        ${neoforge}/libraries/net/neoforged/neoforge/${neoforgeVersion}/unix_args.txt > $out
    '';
  };
in
{
  inherit minecraftVersion neoforgeVersion neoforge;

  # Unpacked server pack: mods/, config/, defaultconfigs/, server.properties.
  pack = stdenvNoCC.mkDerivation {
    pname = "all-of-create-serverpack";
    version = "2.6";

    # CurseForge project 885460, server file 9164660.
    src = fetchurl {
      url = "https://mediafilez.forgecdn.net/files/9164/660/All_of_Create_v2.6_serverpack.zip";
      sha256 = "62d50ce36847068ecb40e1653f2f5e3bfedf8c8d4daffbb645055536e21b67d0";
    };

    nativeBuildInputs = [ unzip ];
    sourceRoot = ".";

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r mods config defaultconfigs server.properties server-icon.png $out/
      runHook postInstall
    '';
    dontFixup = true;
  };

  # Launches NeoForge from the current directory (the server data dir).
  # Arguments are JVM options, as services.minecraft-server passes jvmOpts.
  launcher = writeShellScriptBin "minecraft-server" ''
    exec ${lib.getExe jre} "$@" @${argsFile} nogui
  '';
}

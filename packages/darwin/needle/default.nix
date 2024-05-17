{
  stdenv,
  fetchFromGitHub,
  swift,
  swiftpm,
  swiftpm2nix,
  sqlite,
}: let
  # Pass the generated files to the helper.
  generated = swiftpm2nix.helpers ./nix;
in
  stdenv.mkDerivation rec {
    name = "needle-" + version;
    version = "0.24.0";

    src = fetchFromGitHub {
      owner = "uber";
      repo = "needle";
      rev = "v${version}";
      hash = "sha256-vQlUcfIj+LHZ3R+XwSr9bBIjcZUWkW2k/wI6HF+sDPo=";
    };

    sourceRoot = "${src.name}/Generator";

    nativeBuildInputs = [swift swiftpm];

    propagatedBuildInputs = [
      sqlite
    ];

    configurePhase = generated.configure;

    installPhase = ''
      runHook preInstall
      binPath="$(swiftpmBinPath)"
      mkdir -p $out/bin
      cp $binPath/needle $out/bin/
      runHook postInstall
    '';
  }

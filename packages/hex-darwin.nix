{
  stdenvNoCC,
  fetchurl,
  unzip,
  version,
}:
stdenvNoCC.mkDerivation {
  pname = "hex";
  inherit version;

  # Upstream's signed, notarized release. Building from source would leave an
  # ad-hoc signature that changes every rebuild, and macOS would drop the
  # Microphone and Accessibility grants with it. A version bump changes the
  # URL, so the hash fails until it is updated here.
  src = fetchurl {
    url = "https://github.com/anomalyco/hex/releases/download/v${version}/hex-${version}-macos-arm64.zip";
    hash = "sha256-HCjWoeeQMj7xmbSBvJIx5q2OcKF4W+hJE+Cnvwpuuzk=";
  };

  nativeBuildInputs = [ unzip ];
  sourceRoot = ".";
  # Any fixup (stripping, shebang patching) would break the code signature.
  dontFixup = true;

  installPhase = ''
    mkdir -p $out/Applications
    cp -R Hex.app $out/Applications/
  '';

  meta.platforms = [ "aarch64-darwin" ];
}

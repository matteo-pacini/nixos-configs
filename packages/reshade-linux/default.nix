{
  lib,
  stdenvNoCC,
  fetchurl,
  writers,
  _7zz,
  coreutils,
  git,
  gnugrep,
}:
let
  version = "6.8.0";

  setup = {
    reshade = fetchurl {
      url = "https://reshade.me/downloads/ReShade_Setup_${version}.exe";
      hash = "sha256-IHrqFiBfv5UryP4YeZZmckVM8EAC5600I3x5kKWzwLQ=";
    };
    reshade-addon = fetchurl {
      url = "https://reshade.me/downloads/ReShade_Setup_${version}_Addon.exe";
      hash = "sha256-r+TI8TBIMGMHmDuLPUHVvwCoaCBECw5X3qEJUOEXZEU=";
    };
  };

  # Same DLLs and hashes winetricks uses (taken from Firefox 102.5esr), pinned to
  # a commit so upstream force-pushes cannot change them under us.
  fxc2 = "https://raw.githubusercontent.com/mozilla/fxc2/9aba9b11079303d5577e0e3eb455f4d00f3b5946/dll";
  d3dcompiler = {
    "32" = fetchurl {
      url = "${fxc2}/d3dcompiler_47_32.dll";
      hash = "sha256-KtDUmH/EYkVmsZDnR8nZUDhEOVbtgWq/0eLTibXsCFE=";
    };
    "64" = fetchurl {
      url = "${fxc2}/d3dcompiler_47.dll";
      hash = "sha256-RDK70aOQh08/ClA9RcxI00arw6jAITwon0thW/DuhPM=";
    };
  };

  dist = stdenvNoCC.mkDerivation {
    pname = "reshade-dist";
    inherit version;
    dontUnpack = true;
    nativeBuildInputs = [ _7zz ];
    installPhase = ''
      runHook preInstall
      7zz e -y -o"$out/reshade" ${setup.reshade}
      7zz e -y -o"$out/reshade-addon" ${setup.reshade-addon}
      test -f "$out/reshade/ReShade64.dll" && test -f "$out/reshade-addon/ReShade32.dll"
      install -Dm0644 ${d3dcompiler."32"} "$out/d3dcompiler_47/d3dcompiler_47.dll.32"
      install -Dm0644 ${d3dcompiler."64"} "$out/d3dcompiler_47/d3dcompiler_47.dll.64"
      install -Dm0644 ${./labels.nuon} "$out/labels.nuon"
      runHook postInstall
    '';
  };
in
(writers.writeNuBin "reshade-linux" {
  makeWrapperArgs = [
    "--prefix"
    "PATH"
    ":"
    (lib.makeBinPath [
      coreutils
      git
      gnugrep
    ])
    "--set"
    "RESHADE_DIST"
    "${dist}"
    "--set"
    "RESHADE_VERSION_PINNED"
    version
  ];
} ./reshade-linux.nu).overrideAttrs
  (old: {
    meta = old.meta // {
      description = "Install ReShade into Wine/Proton games and keep its shaders up to date";
      platforms = [ "x86_64-linux" ];
    };
  })

{
  lib,
  stdenv,
  buildDotnetModule,
  fetchFromGitHub,
  dotnetCorePackages,
  copyDesktopItems,
  makeDesktopItem,

  # Avalonia 11 runtime libs (dlopen-ed → wrapped into LD_LIBRARY_PATH).
  libx11,
  libice,
  libsm,
  libxi,
  libxcursor,
  libxext,
  libxrandr,
  fontconfig,
  glew,
  libGL,
}:

buildDotnetModule (finalAttrs: {
  pname = "optiscaler-client";
  version = "1.0.5";

  src = fetchFromGitHub {
    owner = "Agustinm28";
    repo = "Optiscaler-Client";
    rev = "5072a0761bb6dfbf7e52cc9e4b5c0cde49e1d209";
    hash = "sha256-1Cs6DHR7f5MtklmKY96+uOi4esFP2VkAWsR/j9bwdqs=";
  };

  dotnet-sdk = dotnetCorePackages.sdk_10_0;
  dotnet-runtime = dotnetCorePackages.runtime_10_0;

  nugetDeps = ./optiscaler-client-deps.json;

  projectFile = [ "OptiscalerClient.csproj" ];

  # Pin a single RID so deps are gathered for linux-x64 only.
  runtimeId = "linux-x64";

  # csproj forces self-contained single-file publish (PublishSingleFile /
  # SelfContained / PublishReadyToRun / EnableCompressionInSingleFile), which
  # fights buildDotnetModule's framework-dependent model. Neutralize them.
  dotnetFlags = [
    "-p:PublishSingleFile=false"
    "-p:SelfContained=false"
    "-p:PublishReadyToRun=false"
    "-p:EnableCompressionInSingleFile=false"
  ];

  executables = [ "OptiscalerClient" ];

  nativeBuildInputs = [ copyDesktopItems ];

  # Avalonia desktop on Linux dlopens these at runtime.
  # libGL = GPU rendering (software fallback without it); X11 set + fontconfig
  # for windowing/text; glew for GL extension loading.
  runtimeDeps = [
    libx11
    libice
    libsm
    libxi
    libxcursor
    libxext
    libxrandr
    fontconfig
    glew
    libGL
  ];

  desktopItems = [
    (makeDesktopItem {
      name = "OptiscalerClient";
      exec = "OptiscalerClient";
      icon = "OptiscalerClient";
      desktopName = "OptiScaler Client";
      comment = finalAttrs.meta.description;
      categories = [ "Utility" ];
      terminal = false;
    })
  ];

  postInstall = ''
    install -Dm644 assets/icon.png \
      $out/share/icons/hicolor/256x256/apps/OptiscalerClient.png
  '';

  meta = {
    description = "Desktop GUI for installing, managing, and updating the OptiScaler upscaling mod across a game library";
    homepage = "https://github.com/Agustinm28/Optiscaler-Client";
    license = lib.licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
    mainProgram = "OptiscalerClient";
  };
})

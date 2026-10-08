{
  lib,
  appimageTools,
  fetchurl,
  makeWrapper,
}:

let
  version = "0.16.3";
in
appimageTools.wrapType2 {
  pname = "exiled-exchange-2";
  inherit version;

  src = fetchurl {
    url = "https://github.com/Kvan7/Exiled-Exchange-2/releases/download/v${version}/Exiled-Exchange-2-${version}.AppImage";
    hash = "sha256-aAHFELdlL7cccpzAW9ROHF1hZDAnQGTLLtDonS0CT2Q=";
  };

  nativeBuildInputs = [ makeWrapper ];

  # ee2 wraps the FHS launcher, forcing X11 mode (Electron on Wayland is broken for this app).
  extraInstallCommands = ''
    makeWrapper $out/bin/exiled-exchange-2 $out/bin/ee2 \
      --set XDG_SESSION_TYPE x11 \
      --add-flags "--ozone-platform=x11"
  '';

  meta = {
    description = "Path of Exile 2 trade overlay";
    homepage = "https://github.com/Kvan7/Exiled-Exchange-2";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "ee2";
  };
}

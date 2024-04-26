final: prev: {
  telegram-desktop =
    prev.telegram-desktop.overrideAttrs
    (old: {
      buildInputs = old.buildInputs ++ [prev.makeWrapper];
      postInstall =
        old.postInstall
        or ""
        + ''
          wrapProgram "$out/bin/telegram-desktop" --set QT_QPA_PLATFORM xcb
        '';
    });
}

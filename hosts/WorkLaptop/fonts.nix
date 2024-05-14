{
  config,
  pkgs,
  lib,
  ...
}: {
  fonts.fontDir.enable = true;
  fonts.fonts = with pkgs; [
    (nerdfonts.override {fonts = ["FiraCode"];})
  ];
}

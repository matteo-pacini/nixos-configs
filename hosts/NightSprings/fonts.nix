{
  config,
  pkgs,
  lib,
  ...
}: {
  fonts.fontDir.enable = true;
  fonts.fonts = with pkgs; [
    meslo-lgs-nf
  ];
}

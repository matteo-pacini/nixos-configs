{ config, pkgs, ... }:
{
  fonts.fontconfig.enable = true;
  fonts.fontDir.enable = true;

  fonts.packages = with pkgs; [ (nerdfonts.override { fonts = [ "FiraCode" ]; }) ];
}

{ pkgs, ... }:
{
  fonts.fontconfig.enable = true;
  fonts.fontDir.enable = true;

  fonts.packages = [
    pkgs.nerd-fonts.fira-code
  ];
}

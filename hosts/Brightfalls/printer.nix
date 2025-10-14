{
  pkgs,
  lib,
  isVM,
  ...
}:
{
  services.printing.enable = lib.mkIf (!isVM) true;
  services.printing.drivers = [ pkgs.brlaser ];
}

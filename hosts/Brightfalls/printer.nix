{
  config,
  pkgs,
  lib,
  ...
}:
{
  services.printing.enable = true;
  services.printing.drivers = [ pkgs.brlaser ];
}

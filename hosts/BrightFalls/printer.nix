{ pkgs, ... }:
{
  services.printing.enable = true;
  services.printing.drivers = [ pkgs.brlaser ];
  # Its D-Bus service and udev rules set up USB printers; the program is the
  # printer settings window.
  services.system-config-printer.enable = true;
  programs.system-config-printer.enable = true;
}

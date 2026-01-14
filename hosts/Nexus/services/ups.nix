{ ... }:
{
  services.apcupsdMulti.upses = {
    rack-ups = {
      enable = true;
      nisPort = 3551;
      configText = ''
        UPSNAME   rack-ups
        UPSCABLE  ether
        UPSTYPE   snmp
        DEVICE    192.168.10.43:161:APC:Nexus
        POLLTIME  15

        # ---------- monitor-only; disable every shutdown trigger ----------
        ONBATTERYDELAY 0     # still logs the instant ONBATT event
        BATTERYLEVEL   0     # 0 → never act on %-charge threshold
        MINUTES        0     # 0 → never act on remaining-minutes
        TIMEOUT        0     # 0 → disables the failsafe timer
      '';
    };

    server-ups = {
      enable = true;
      nisPort = 3552;
      configText = ''
        UPSNAME   server-ups
        UPSCABLE  usb
        UPSTYPE   usb
        DEVICE    /dev/ups-server
        POLLTIME  15

        # ---------- shutdown triggers for Nexus ----------
        ONBATTERYDELAY 6     # seconds before reacting to power loss
        BATTERYLEVEL   10    # shutdown at 10% battery
        MINUTES        5     # shutdown with 5 minutes remaining
        TIMEOUT        0     # no fixed timeout
      '';
    };
  };

  # udev rule to create stable symlink for server UPS
  services.udev.extraRules = ''
    SUBSYSTEM=="usb", ATTR{idVendor}=="051d", ATTR{idProduct}=="0003", ATTR{serial}=="IS1124011060  ", SYMLINK+="ups-server", MODE="0660"
  '';
}

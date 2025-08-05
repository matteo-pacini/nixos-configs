{ ... }:
{
  services.apcupsd = {
    enable = true;
    configText = ''
      UPSNAME   rack-ups
      UPSCABLE  ether
      UPSTYPE   snmp
      DEVICE    192.168.10.43:161:APC:Nexus   
      POLLTIME  15                           

      # ---------- monitor-only; disable every shutdown trigger ----------
      ONBATTERYDELAY 0     # still logs the instant ONBATT event
      BATTERYLEVEL   0     # 0 → never act on %-charge threshold *
      MINUTES        0     # 0 → never act on remaining-minutes *
      TIMEOUT        0     # 0 → disables the failsafe timer :contentReference[oaicite:0]{index=0}

    '';
  };
}

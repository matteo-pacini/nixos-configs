{ ... }:

{
  users.users."nzbget" = {
    extraGroups = [ "downloads" ];
  };

  systemd.tmpfiles.rules = [
    "d /downloads/usenet 2770 nzbget downloads"
  ];

  services.nzbget = {
    enable = true;
    group = "downloads";
  };
}

{ ... }:
{
  imports = [
    ./openssh.nix
    ./smartd.nix
    ./jellyfin.nix
    ./backup.nix
    ./nzbget.nix
  ];

  systemd.tmpfiles.rules = [
    "d /downloads        2770 matteo downloads"
    "d /downloads/usenet 2770 nzbget downloads"
  ];

  # To control /diskpool/media access
  users.groups.media = { };

  # To control /diskpool/downloads access
  users.groups.downloads = { };
}

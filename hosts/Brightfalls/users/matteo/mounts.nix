{ lib, isVM, ... }:
{
  systemd.user.tmpfiles.rules = lib.mkIf (!isVM) [
    "d /home/matteo/Mounts/Games 0700 matteo users"
  ];

  systemd.user.mounts.home-matteo-Mounts-Games = lib.mkIf (!isVM) {
    Unit = {
      Description = "Games folder on nexus";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };

    Install = {
      WantedBy = [ "default.target" ];
    };

    Mount = {
      What = "matteo@nexus:/diskpool/games";
      Where = "/home/matteo/Mounts/Games";
      Type = "fuse.sshfs";
      Options = "port=1788,idmap=user,_netdev,IdentityFile=/home/matteo/.ssh/nexus,x-systemd.automount";
      TimeoutSec = 60;
    };
  };

}

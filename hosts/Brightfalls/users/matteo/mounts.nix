{ ... }:
{
  systemd.user.tmpfiles.rules = [
    "d /home/matteo/Mounts/Games 0700 matteo users -"
    "d /home/matteo/Mounts/Music 0700 matteo users -"
  ];

  systemd.user.mounts.home-matteo-Mounts-Games = {
    Unit = {
      Description = "Games folder on nexus";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };

    Install = {
      WantedBy = [ "default.target" ];
    };

    Mount = {
      What = "matteo@192.168.7.7:/diskpool/games";
      Where = "/home/matteo/Mounts/Games";
      Type = "fuse.sshfs";
      Options = "port=1788,idmap=user,_netdev,IdentityFile=/home/matteo/.ssh/nexus,x-systemd.automount";
      TimeoutSec = 60;
    };
  };

  systemd.user.mounts.home-matteo-Mounts-Music = {
    Unit = {
      Description = "Music folder on nexus";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };

    Install = {
      WantedBy = [ "default.target" ];
    };

    Mount = {
      What = "matteo@192.168.7.7:/diskpool/music";
      Where = "/home/matteo/Mounts/Music";
      Type = "fuse.sshfs";
      Options = "port=1788,idmap=user,_netdev,IdentityFile=/home/matteo/.ssh/nexus,x-systemd.automount";
      TimeoutSec = 60;
    };
  };
}

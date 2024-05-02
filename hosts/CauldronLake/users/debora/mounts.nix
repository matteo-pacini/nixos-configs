{
  config,
  pkgs,
  inputs,
  ...
}: {
  systemd.user.tmpfiles.rules = [
    "d /home/debora/Mounts/Debora 0700 debora users -"
  ];

  systemd.user.mounts.home-debora-Mounts-Debora = {
    Unit = {
      Description = "Debora folder on nexus";
      After = [
        "network-online.target"
      ];
      Wants = [
        "network-online.target"
      ];
    };

    Install = {WantedBy = ["default.target"];};

    Mount = {
      What = "debora@192.168.7.7:/diskpool/debora";
      Where = "/home/debora/Mounts/Debora";
      Type = "fuse.sshfs";
      Options = "port=1788,idmap=user,_netdev,IdentityFile=/home/debora/.ssh/nexus,x-systemd.automount";
      TimeoutSec = 60;
    };
  };
}

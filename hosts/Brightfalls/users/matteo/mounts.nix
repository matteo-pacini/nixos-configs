{
  config,
  pkgs,
  inputs,
  ...
}: {
  systemd.user.mounts.games = {
    Unit = {
      Description = "Games folder on nexus";
      After = [
        "network-online.target"
      ];
      Requires = [
        "network-online.target"
      ];
    };

    Install = {WantedBy = ["multi-user.target"];};

    Mount = {
      What = "matteo@192.168.7.7:/diskpool/games";
      Where = "/home/matteo/Games/Mounts";
      Type = "fuse.sshfs";
      Options = "port=1788,idmap=user";
    };
  };
}

{ lib, isVM, ... }:
{
  systemd.user.tmpfiles.settings = lib.mkIf (!isVM) {
    "10-mounts".rules = {
      "/home/matteo/Mounts/Games".d = {
        mode = "0700";
        user = "matteo";
        group = "users";
      };
    };
  };

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

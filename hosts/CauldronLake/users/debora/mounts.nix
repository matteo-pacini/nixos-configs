{ ... }:
{
  systemd.user.tmpfiles.settings = {
    "10-mounts".rules = {
      "/home/debora/Mounts/Debora".d = {
        mode = "0700";
        user = "debora";
        group = "users";
      };
    };
  };

  systemd.user.mounts.home-debora-Mounts-Debora = {
    Unit = {
      Description = "Debora folder on nexus";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };

    Install = {
      WantedBy = [ "default.target" ];
    };

    Mount = {
      What = "debora@nexus:/diskpool/debora";
      Where = "/home/debora/Mounts/Debora";
      Type = "fuse.sshfs";
      Options = "port=1788,idmap=user,_netdev,IdentityFile=/home/debora/.ssh/id_ed25519,x-systemd.automount";
      TimeoutSec = 60;
    };
  };

}

{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.herdr;
in
{
  options.custom.herdr = {
    enable = lib.mkEnableOption "herdr terminal multiplexer";
    server = lib.mkEnableOption "headless herdr server as a systemd user service (Linux only)";
  };

  config = lib.mkIf cfg.enable {
    programs.herdr = {
      enable = true;
      settings = {
        # ~/.ssh/config is a read-only Home Manager symlink (custom.ssh),
        # so herdr must not try to edit it when adding remote hosts.
        remote.manage_ssh_config = false;
      };
    };

    # Keeps sessions and agents alive without an attached client. Pair with
    # users.users.<user>.linger = true on headless hosts so it starts at
    # boot instead of at first login.
    systemd.user.services.herdr-server = lib.mkIf cfg.server {
      Unit.Description = "herdr headless server";
      Service = {
        ExecStart = "${lib.getExe config.programs.herdr.package} server";
        Restart = "on-failure";
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}

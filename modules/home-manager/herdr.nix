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
        # Closing a worktree subspace leaves the checkout on disk; deleting it
        # is a separate action that ships unbound. Displaces close_tab, which
        # holds this chord by default.
        keys.remove_worktree = "prefix+shift+x";
        # Claude panes get a third row for the context meter. The $context
        # token and the "claude - <model> (<effort>)" agent label are reported
        # by the statusLine wrapper in modules/home-manager/claude-code.nix.
        ui.sidebar.agents.rows_by_agent.claude = [
          [
            "state_icon"
            "workspace"
            "tab"
          ]
          [ "agent" ]
          [ "$context" ]
        ];
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

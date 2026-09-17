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
        # Claude panes get a third row for the context meter. The $ctx/$ctxk
        # tokens and the "claude - <model> (<effort>)" agent label are reported
        # by the statusLine wrapper in modules/home-manager/claude-code.nix.
        # The pane name carries the identity here, so it takes the bold slot
        # workspace would otherwise hold; the agent panel groups by space
        # already, which is why workspace is absent from the row.
        ui.sidebar.agents.rows_by_agent.claude = [
          [
            "state_icon"
            {
              token = "pane";
              bold = true;
              # Explicit: omitted style fields inherit the contextual default,
              # and these tokens default to dim, which cancels out the bold.
              dim = false;
              # Bold alone is imperceptible against the token's default grey,
              # so the name also takes the bright foreground.
              fg = "#f8f8f2";
            }
            {
              token = "tab";
              dim = true;
            }
          ]
          [
            {
              token = "agent";
              bold = true;
              # Explicit: omitted style fields inherit the contextual default,
              # and these tokens default to dim, which cancels out the bold.
              dim = false;
            }
          ]
          [
            # Bands track auto-compact, which fires at 80% of the window: green
            # below half, amber from half, red within ten points of the limit.
            # First matching rule wins, so these run severe to mild, and the
            # green case is the base fg because a rule needs a predicate.
            {
              token = "$ctx";
              fg = "#50FA7B";
              rules = [
                {
                  gt = 69.9;
                  fg = "#FF5555";
                  bold = true;
                }
                {
                  gt = 49.9;
                  fg = "#FFB86C";
                }
              ];
            }
            {
              token = "$ctxk";
              dim = true;
            }
          ]
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

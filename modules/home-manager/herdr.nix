{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.herdr;

  # Reports the tokens agentRows renders. Called by the Claude statusLine
  # (modules/home-manager/claude-code), a Codex hook and an opencode plugin.
  agentReport = pkgs.writeShellApplication {
    name = "herdr-agent-report";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = builtins.readFile ./herdr/agent-report.sh;
  };

  # Agent identity, model, then context and prompt cache. A token nobody has
  # reported yet drops out along with its separator.
  agentRows = [
    [
      "state_icon"
      {
        token = "$title";
        bold = true;
        # Explicit: omitted style fields inherit the contextual default,
        # which is dim and cancels out the bold.
        dim = false;
        fg = "#f8f8f2";
      }
    ]
    [
      {
        token = "$model";
        dim = false;
      }
    ]
    [
      # One of the three is set at a time; herdr-agent-report picks the band.
      {
        token = "$ctx_ok";
        fg = "#50FA7B";
      }
      {
        token = "$ctx_warn";
        fg = "#FFB86C";
      }
      {
        token = "$ctx_hot";
        fg = "#FF5555";
        bold = true;
      }
      {
        token = "$ctxk";
        dim = true;
      }
      {
        token = "$cache";
        fg = "#6272A4";
        rules = [
          {
            equals = "cache cold";
            fg = "#FF5555";
            bold = true;
          }
          {
            starts_with = "cache <";
            fg = "#FFB86C";
          }
        ];
      }
    ]
  ];
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
        ui.sidebar_width = 36;
        ui.sidebar_max_width = 48;
        ui.sidebar.agents.rows_by_agent = {
          claude = agentRows;
          codex = agentRows;
          opencode = agentRows;
        };
      };
    };

    # herdr's own state hooks (installed by `herdr integration install`) bail
    # out early without python3 on PATH.
    home.packages = [
      agentReport
      pkgs.python3
    ];

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

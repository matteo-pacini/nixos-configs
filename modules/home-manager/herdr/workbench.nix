# The desktop app's `workbench` layout and the mods drawn in it.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.herdr;
  modsHome = "${config.xdg.configHome}/herdr-app/mods";

  # Every mod folder under mods/, as installed. Symlinks are followed, so a mod
  # may link in files from elsewhere in the tree and still install as a plain
  # folder: herdr-app (0.1.10) reports "no `main.js`" when a mod's main.js is a
  # symlink.
  mods = pkgs.runCommand "herdr-mods" { } ''
    cp -rL ${./mods} $out
  '';

  # Installed with the layout; the optional ones only when enabled.
  enabledMods = [
    "agent-list"
    "pane-header"
    "pane-menu"
  ]
  ++ lib.optional cfg.workbench.fleet.enable "fleet"
  ++ lib.optional cfg.workbench.nixpkgsPrs.enable "nixpkgs-prs"
  ++ lib.optional cfg.workbench.spaceCards.enable "space-cards";

  workbenchLayout = pkgs.writeText "workbench.json" (
    builtins.toJSON (
      import ./layout.nix { inherit lib; } {
        fleet = cfg.workbench.fleet.enable;
        nixpkgsPrs = cfg.workbench.nixpkgsPrs.enable;
        spaceCards = cfg.workbench.spaceCards.enable;
      }
    )
  );

  needsWorkbench = name: {
    assertion = cfg.workbench.enable;
    message = "custom.herdr.workbench.${name} lives in the workbench layout; enable custom.herdr.workbench.";
  };
in
{
  options.custom.herdr.workbench = {
    enable = lib.mkEnableOption ''
      the desktop app's `workbench` layout: the `agent-list` Agents sidebar (agents
      by machine and space, those that need you pinned on top, each named by its
      `agent.name` terminal label, with Claude's model, effort, context fill and
      prompt-cache time left) and the `pane-header` pane header (outdated agents
      restart on the installed version). The first activation with the app open shows it
    '';
    fleet.enable = lib.mkEnableOption ''
      the nixos-configs panel in the workbench layout: the deploy pipeline
      (master, build.yml, the deploy branch, each host's comin) above the
      repo's WAIT-FOR / WATCH tags and their upstream status. Shown only while
      the focused terminal is in a checkout of this repo. Needs `gh` signed in
      and SSH to the other hosts
    '';
    nixpkgsPrs.enable = lib.mkEnableOption ''
      the nixpkgs panel in the workbench layout: open NixOS/nixpkgs PRs that
      involve you, with nixpkgs-review or a Claude Code review a right-click away.
      Shown only while the focused terminal is in a nixpkgs checkout. Needs `gh` signed in
    '';
    spaceCards.enable = lib.mkEnableOption ''
      the `space-cards` Spaces list in the workbench layout, in place of the shipped one:
      each machine a card with its device icon, OS and connection state, each space
      with its branch badge, ahead/behind the default branch, and a worktree badge
    '';
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions =
          lib.optional cfg.workbench.enable {
            assertion = cfg.desktop;
            message = "custom.herdr.workbench needs custom.herdr.desktop.";
          }
          ++ lib.optional cfg.workbench.fleet.enable (needsWorkbench "fleet")
          ++ lib.optional cfg.workbench.nixpkgsPrs.enable (needsWorkbench "nixpkgsPrs")
          ++ lib.optional cfg.workbench.spaceCards.enable (needsWorkbench "spaceCards");
      }

      (lib.mkIf cfg.workbench.enable {

        # Copied, not linked (see `mods`), so mods can be tried live in place. Each
        # folder is replaced whole, hand edits and stale files included; the app
        # regenerates its own typings in it on start. A mod that is turned off is
        # left where it is.
        home.activation.herdrWorkbenchMods = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          for mod in ${lib.escapeShellArgs enabledMods}; do
            run rm -rf "${modsHome}/$mod"
            run mkdir -p "${modsHome}"
            run cp -r --no-preserve=mode "${mods}/$mod" "${modsHome}/$mod"
          done
          # Their earlier names.
          for old in claude-pane agent-tree agent-pane deploy; do
            run rm -rf "${modsHome}/$old"
          done
        '';

        # A snapshot of herdr-app's shipped `main` layout, adjusted by layout.nix;
        # shipped layouts live in the binary, so re-snapshot it when upstream
        # changes `main`. Copied, not linked, so mods can be tried in it live; each
        # activation replaces it, first saving a copy that differs from the one
        # activation last wrote (a hand edit) to the state folder.
        home.activation.herdrWorkbenchLayoutFile = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          file="${config.xdg.configHome}/herdr-app/layouts/workbench.json"
          last="${config.xdg.stateHome}/herdr-app/workbench.json"
          if [ -f "$file" ] && [ ! -L "$file" ] && ! cmp -s "$file" "$last"; then
            run install -Dm644 "$file" "${config.xdg.stateHome}/herdr-app/workbench.$(date +%Y%m%d-%H%M%S).json"
          fi
          run rm -f "$file"
          run install -Dm644 ${workbenchLayout} "$file"
          run install -Dm644 ${workbenchLayout} "$last"
        '';

        # Shows the layout once per machine, so a later pick of another layout
        # sticks. A running window switches at once. With none open (activation
        # at boot), the app's shared.json, where it keeps the shown layout, is set
        # so the next start opens on it.
        home.activation.herdrWorkbenchLayout =
          let
            herdrApp = lib.getExe' pkgs.herdr-desktop "herdr-app";
          in
          lib.hm.dag.entryAfter [ "herdrWorkbenchLayoutFile" ] ''
            marker="${config.xdg.stateHome}/herdr-app/workbench-shown"
            shared="${config.xdg.configHome}/herdr-app/shared.json"
            if [ ! -e "$marker" ]; then
              shown=0
              if ${herdrApp} status >/dev/null 2>&1; then
                run ${herdrApp} do layout.switch --name workbench >/dev/null && shown=1
              else
                tmp=$(mktemp)
                { cat "$shared" 2>/dev/null || echo '{}'; } |
                  ${lib.getExe pkgs.jq} '.layout = "workbench"' >"$tmp" &&
                  run install -Dm644 "$tmp" "$shared" && shown=1
                rm -f "$tmp"
              fi
              if [ "$shown" = 1 ]; then
                run mkdir -p "$(dirname "$marker")"
                run touch "$marker"
              fi
            fi
          '';
      })
    ]
  );
}

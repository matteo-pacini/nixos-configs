{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.herdr;

  # Claude panes come back from a reboot as plain shells; these two put
  # `claude --resume <id>` back in them. See the scripts' headers.
  claudeSession = pkgs.writeShellApplication {
    name = "herdr-claude-session";
    runtimeInputs = [
      pkgs.herdr-core
      pkgs.jq
    ];
    text = builtins.readFile ./herdr/claude-session.sh;
  };
  claudeResume = pkgs.writeShellApplication {
    name = "herdr-claude-resume";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.herdr-core
      pkgs.jq
    ];
    text = builtins.readFile ./herdr/claude-resume.sh;
  };

  # Sets the context, cache, model and effort labels the agent-tree mod draws, then renders
  # ccstatusline as the plain statusLine does.
  claudeStatusLine = pkgs.writeShellApplication {
    name = "claude-statusline";
    runtimeInputs = [
      pkgs.jq
      pkgs.herdr-core
    ];
    text = builtins.readFile ./herdr/claude-statusline.sh;
  };

  # The same labels for Codex, from its hooks. On PATH under a fixed name, not
  # as a store path: Codex skips a hook until it's trusted (/hooks), and keys
  # that trust on the hook's definition, so a path that changes every rebuild
  # would need trusting again each time.
  codexLabels = pkgs.writeShellApplication {
    name = "herdr-codex-labels";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.herdr-core
      pkgs.jq
    ];
    text = builtins.readFile ./herdr/codex-labels.sh;
  };

  # Sets and clears `agent.ask`, what a waiting agent asks, from Claude Code's
  # and Codex's hooks; the office view draws it. On PATH under a fixed name for
  # the same reason as herdr-codex-labels.
  agentAsk = pkgs.writeShellApplication {
    name = "herdr-agent-ask";
    runtimeInputs = [
      pkgs.herdr-core
      pkgs.jq
    ];
    text = builtins.readFile ./herdr/agent-ask.sh;
  };
  agentAskHook = [
    {
      hooks = [
        {
          type = "command";
          command = "herdr-agent-ask";
        }
      ];
    }
  ];

  # The office view's people: one SVG per pose and app, from the pixel maps.
  officeSprites = pkgs.runCommand "herdr-office-sprites" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
    node ${./herdr/agent-tree/sprites}/render.mjs "$out"
  '';

  # The agent-tree layout, adjusted for the mods that live in it: agent-pane
  # as the pane header, the deploy block beside the work area (mods.deploy),
  # and space-cards in place of the shipped spaces list (mods.spaceCards).
  # Generated rather than a second snapshot of `main`.
  agentTreeLayout =
    let
      deployBlock = {
        id = "deploy";
        type = "block";
        content.mod = "deploy";
        size.px = 340;
        min = 280;
        max = 600;
      };
      adjust =
        node:
        if node.id or null == "main" then
          lib.recursiveUpdate node { content.pane.header.content.mod = "agent-pane"; }
        else if node.id or null == "work-body" && cfg.mods.deploy.enable then
          node // { children = node.children ++ [ deployBlock ]; }
        else if node.id or null == "spaces" && cfg.mods.spaceCards.enable then
          node
          // {
            content = node.content // {
              mod = "space-cards";
            };
          }
        else if node ? children then
          node // { children = map adjust node.children; }
        else
          node;
    in
    pkgs.writeText "agent-tree.json" (
      builtins.toJSON (adjust (lib.importJSON ./herdr/layouts/agent-tree.json))
    );
in
{
  options.custom.herdr = {
    enable = lib.mkEnableOption "herdr-core (`hc`), the server that runs Herdr's terminals and agents";
    desktop = lib.mkEnableOption "the Herdr desktop app";
    mods.agentTree.enable = lib.mkEnableOption ''
      the desktop app's `agent-tree` layout: the Agents sidebar as host > space > tab > agent,
      each agent named by its `agent.name` terminal label, with Claude's model, effort,
      context fill and prompt-cache time left. The first activation with the app open shows it
    '';
    mods.deploy.enable = lib.mkEnableOption ''
      the nixos-configs panel in the agent-tree layout: the deploy pipeline
      (master, build.yml, the deploy branch, each host's comin) above the
      repo's WAIT-FOR / WATCH tags and their upstream status. Shown only while
      the focused terminal is in a checkout of this repo. Needs `gh` signed in
      and SSH to the other hosts
    '';
    mods.spaceCards.enable = lib.mkEnableOption ''
      the `space-cards` Spaces list in the agent-tree layout, in place of the shipped one:
      each machine a card with its device icon, OS and connection state, each space
      with its branch badge, ahead/behind the default branch, and a worktree badge
    '';
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        home.packages = [ pkgs.herdr-core ] ++ lib.optional cfg.desktop pkgs.herdr-desktop;

        # Offered in the desktop app's theme picker. Only the theme file is managed:
        # the picked theme lives in herdr-app's own writable layout state.
        xdg.configFile."herdr-app/themes/dracula.json" = lib.mkIf cfg.desktop {
          source = ./herdr/dracula.json;
        };

        # Declared here because the claude-code module rewrites settings.json on
        # every activation, dropping hooks added any other way.
        custom.claude-code.extraSettings = lib.mkIf config.custom.claude-code.enable {
          hooks = {
            SessionStart = [
              {
                hooks = [
                  {
                    type = "command";
                    command = "${lib.getExe claudeSession} start";
                  }
                ];
              }
            ];
            SessionEnd = [
              {
                hooks = [
                  {
                    type = "command";
                    command = "${lib.getExe claudeSession} end";
                  }
                ];
              }
            ];
          }
          # The office view's agent.ask: set when a prompt shows, cleared by the
          # rest. A denied prompt fires none of them.
          // lib.optionalAttrs cfg.mods.agentTree.enable {
            PermissionRequest = agentAskHook;
            PostToolUse = agentAskHook;
            UserPromptSubmit = agentAskHook;
            Stop = agentAskHook;
          };
        };

        systemd.user.services.herdr-claude-resume = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
          Unit.Description = "Resume Claude sessions in recovered herdr-core terminals";
          Service = {
            ExecStart = lib.getExe claudeResume;
            Restart = "always";
            RestartSec = 5;
          };
          Install.WantedBy = [ "default.target" ];
        };

        launchd.agents.herdr-claude-resume = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
          enable = true;
          config = {
            ProgramArguments = [ (lib.getExe claudeResume) ];
            RunAtLoad = true;
            KeepAlive = true;
            StandardOutPath = "${config.home.homeDirectory}/Library/Logs/herdr-claude-resume.log";
            StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/herdr-claude-resume.log";
          };
        };
      }

      (lib.mkIf cfg.mods.agentTree.enable {
        home.packages = [ agentAsk ];

        assertions = [
          {
            assertion = cfg.desktop;
            message = "custom.herdr.mods.agentTree needs custom.herdr.desktop.";
          }
        ];

        # Copied, not linked: herdr-app (0.1.10) reports "no `main.js`" when a mod's
        # main.js is a symlink. The folder is replaced whole, hand-made copies and
        # stale files included; the app regenerates its own typings in it on start.
        home.activation.herdrAgentTreeMod = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          dir="${config.xdg.configHome}/herdr-app/mods/agent-tree"
          run rm -rf "$dir"
          run install -Dm644 ${./herdr/agent-tree/main.js} "$dir/main.js"
          run install -Dm644 ${./herdr/agent-tree/mod.json} "$dir/mod.json"
          run install -Dm644 ${./herdr/agent-tree/office.js} "$dir/office.js"
          run cp -r --no-preserve=mode ${./herdr/agent-tree/office} "$dir/office"
          run cp -r --no-preserve=mode ${officeSprites} "$dir/office/sprites"
          # Its name before it covered Codex and opencode.
          run rm -rf "${config.xdg.configHome}/herdr-app/mods/claude-pane"
          dir="${config.xdg.configHome}/herdr-app/mods/agent-pane"
          run rm -rf "$dir"
          run install -Dm644 ${./herdr/agent-pane/main.js} "$dir/main.js"
          run install -Dm644 ${./herdr/agent-pane/mod.json} "$dir/mod.json"
        '';

        # A snapshot of herdr-app's shipped `main` layout with the agents block
        # swapped; shipped layouts live in the binary, so re-snapshot it when
        # upstream changes `main`. force: replaces hand-made copies instead of
        # failing activation.
        xdg.configFile."herdr-app/layouts/agent-tree.json" = {
          source = agentTreeLayout;
          force = true;
        };

        # Shows the layout once per machine, so a later pick of another layout
        # sticks. A running window switches at once. With none open (activation
        # at boot), the app's shared.json, where it keeps the shown layout, is set
        # so the next start opens on it.
        home.activation.herdrAgentTreeLayout =
          let
            herdrApp = lib.getExe' pkgs.herdr-desktop "herdr-app";
          in
          lib.hm.dag.entryAfter [ "linkGeneration" ] ''
            marker="${config.xdg.stateHome}/herdr-app/agent-tree-shown"
            shared="${config.xdg.configHome}/herdr-app/shared.json"
            if [ ! -e "$marker" ]; then
              shown=0
              if ${herdrApp} status >/dev/null 2>&1; then
                run ${herdrApp} do layout.switch --name agent-tree >/dev/null && shown=1
              else
                tmp=$(mktemp)
                { cat "$shared" 2>/dev/null || echo '{}'; } |
                  ${lib.getExe pkgs.jq} '.layout = "agent-tree"' >"$tmp" &&
                  run install -Dm644 "$tmp" "$shared" && shown=1
                rm -f "$tmp"
              fi
              if [ "$shown" = 1 ]; then
                run mkdir -p "$(dirname "$marker")"
                run touch "$marker"
              fi
            fi
          '';

        custom.claude-code.extraSettings.statusLine = {
          type = "command";
          command = lib.getExe claudeStatusLine;
          padding = 0;
          refreshInterval = 10;
        };
      })

      (lib.mkIf (cfg.mods.agentTree.enable && config.custom.codex.enable) {
        home.packages = [ codexLabels ];

        # hooks.json is Codex's own runtime file (it records trust beside it in
        # config.toml), so the hooks are merged in rather than the file owned.
        home.activation.herdrCodexHooks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          hooks="$HOME/.codex/hooks.json"
          run mkdir -p "$HOME/.codex"
          [ -f "$hooks" ] || echo '{"hooks":{}}' > "$hooks"
          tmp=$(mktemp)
          ${lib.getExe pkgs.jq} '
            .hooks //= {}
            | reduce (
                { command: "herdr-codex-labels", events: ["SessionStart", "Stop", "PostToolUse"] },
                # Codex fires Interrupt when a prompt is denied, PreModelRequest
                # when the model is asked again after one.
                { command: "herdr-agent-ask", events: ["PermissionRequest", "PostToolUse", "UserPromptSubmit", "Interrupt", "PreModelRequest", "Stop"] }
              ) as $hook (.;
                reduce $hook.events[] as $event (.;
                  .hooks[$event] = (
                    (.hooks[$event] // [])
                    | map(.hooks |= map(select(.command != $hook.command)) | select(.hooks != []))
                  ) + [{ hooks: [{ type: "command", command: $hook.command, timeout: 10 }] }]))
          ' "$hooks" > "$tmp" && run mv "$tmp" "$hooks"
          rm -f "$tmp"
        '';
      })

      (lib.mkIf (cfg.mods.agentTree.enable && config.custom.opencode.enable) {
        # Loaded from the plugins folder on start; sets the same labels from
        # opencode's session events.
        xdg.configFile."opencode/plugins/herdr-labels.js".source = ./herdr/opencode-labels.js;
      })

      (lib.mkIf cfg.mods.deploy.enable {
        assertions = [
          {
            assertion = cfg.mods.agentTree.enable;
            message = "custom.herdr.mods.deploy lives in the agent-tree layout; enable custom.herdr.mods.agentTree.";
          }
        ];

        # Copied and replaced whole, like agent-tree above.
        home.activation.herdrDeployMod = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          dir="${config.xdg.configHome}/herdr-app/mods/deploy"
          run rm -rf "$dir"
          run install -Dm644 ${./herdr/deploy/main.js} "$dir/main.js"
          run install -Dm644 ${./herdr/deploy/watch.js} "$dir/watch.js"
          run install -Dm644 ${./herdr/deploy/prompts.js} "$dir/prompts.js"
          run install -Dm644 ${./herdr/deploy/mod.json} "$dir/mod.json"
        '';
      })

      (lib.mkIf cfg.mods.spaceCards.enable {
        assertions = [
          {
            assertion = cfg.mods.agentTree.enable;
            message = "custom.herdr.mods.spaceCards lives in the agent-tree layout; enable custom.herdr.mods.agentTree.";
          }
        ];

        # Copied and replaced whole, like agent-tree above.
        home.activation.herdrSpaceCardsMod = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          dir="${config.xdg.configHome}/herdr-app/mods/space-cards"
          run rm -rf "$dir"
          for f in main.js mod.json desktop.svg laptop.svg server.svg; do
            run install -Dm644 "${./herdr/space-cards}/$f" "$dir/$f"
          done
        '';
      })
    ]
  );
}

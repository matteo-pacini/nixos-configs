# Tests for ../layout.nix, as lib.runTests cases: a list of failures, empty
# when all pass.
{ lib }:
let
  layout = import ../layout.nix { inherit lib; };
  off = layout {
    fleet = false;
    nixpkgsPrs = false;
    spaceCards = false;
  };
  on = layout {
    fleet = true;
    nixpkgsPrs = true;
    spaceCards = true;
  };

  # The node with `id`, or { } when there is none, so a missing node fails the
  # tests that read it instead of aborting evaluation.
  find = id: node: lib.findFirst (n: n != null) { } (findAll id node);
  findAll =
    id: node:
    if node.id or null == id then [ node ] else lib.concatMap (findAll id) (node.children or [ ]);
  ids = node: lib.optional (node ? id) node.id ++ lib.concatMap ids (node.children or [ ]);
in
lib.runTests {
  # layout.nix finds these by id; a re-snapshot that renames one would
  # otherwise drop its adjustment without an error. `sidebar` is read by the
  # mods (lib/ui.js narrow()).
  testSnapshotHasAnchors = {
    expr = lib.all (id: lib.elem id (ids off)) [
      "main"
      "work-body"
      "spaces"
      "agents"
      "sidebar"
      "status"
    ];
    expected = true;
  };
  # Carried in the snapshot itself, not added by layout.nix.
  testAgentsIsAgentList = {
    expr = (find "agents" off).content.mod or null;
    expected = "agent-list";
  };
  testPaneHeader = {
    expr = (find "main" off).content.pane.header.content.mod or null;
    expected = "pane-header";
  };
  testStatusBar = {
    expr = (find "status" off).content.mod or null;
    expected = "status-bar";
  };
  # Only the mod changes: the block keeps its size.
  testStatusBarKeepsTheBlock = {
    expr = (find "status" off).size or null;
    expected = {
      px = 28;
    };
  };
  testTerminalMenu = {
    expr = off.terminal_menu;
    expected = "pane-menu";
  };

  testOffAddsNoBlocks = {
    expr = lib.filter (id: lib.elem id (ids off)) [
      "fleet"
      "nixpkgs-prs"
    ];
    expected = [ ];
  };
  testOffKeepsShippedSpaces = {
    expr = (find "spaces" off).content.mod or null;
    expected = "spaces";
  };

  testOnAppendsSideBlocksInOrder = {
    expr = lib.drop (lib.length ((find "work-body" off).children or [ ])) (
      map (n: n.id) ((find "work-body" on).children or [ ])
    );
    expected = [
      "fleet"
      "nixpkgs-prs"
    ];
  };
  testSideBlockDrawsItsMod = {
    expr = (find "fleet" on).content.mod or null;
    expected = "fleet";
  };
  testOnSwapsSpaces = {
    expr = (find "spaces" on).content.mod or null;
    expected = "space-cards";
  };
  # Only the mod changes: the block keeps its size and the rest of its content.
  testSpaceCardsKeepsTheBlock = {
    expr =
      removeAttrs (find "spaces" on) [ "content" ] == removeAttrs (find "spaces" off) [ "content" ];
    expected = true;
  };
}

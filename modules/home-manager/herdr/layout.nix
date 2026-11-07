# The `workbench` layout: layouts/workbench.json (a snapshot of herdr-app's
# shipped `main` layout) adjusted for the mods that live in it. Pure: takes
# which optional mods are on, returns the layout as an attrset.
#
#   import ./layout.nix { inherit lib; } { fleet = true; nixpkgsPrs = false; spaceCards = true; }
#
# The adjustments find nodes by id (`main`, `work-body`, `spaces`); if a
# re-snapshot renames one, the matching adjustment silently stops applying.
{ lib }:
{
  fleet,
  nixpkgsPrs,
  spaceCards,
}:
let
  sideBlock = mod: {
    id = mod;
    type = "block";
    content.mod = mod;
    size.px = 340;
    min = 280;
    max = 600;
  };
  sideBlocks =
    lib.optional fleet (sideBlock "fleet") ++ lib.optional nixpkgsPrs (sideBlock "nixpkgs-prs");
  adjust =
    node:
    if node.id or null == "main" then
      lib.recursiveUpdate node { content.pane.header.content.mod = "pane-header"; }
    else if node.id or null == "work-body" then
      node // { children = map adjust node.children ++ sideBlocks; }
    else if node.id or null == "spaces" && spaceCards then
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
adjust (lib.importJSON ./layouts/workbench.json) // { terminal_menu = "pane-menu"; }

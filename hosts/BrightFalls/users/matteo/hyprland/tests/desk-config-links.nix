# The desktop's config trees as Home Manager links, read from the evaluated
# configuration (home: BrightFalls' home-manager.users.matteo): user/quickshell,
# user/hypr and user/desk each one read-only link under ~/.config, nothing
# else under them, the reload flag set by quickshell and desk only, the reload
# hook after onFilesChange, and no desk-sync left. Every failure is printed
# by the build; nothing of the system is built.
{ pkgs, home }:
let
  inherit (pkgs) lib;
  files = home.xdg.configFile;
  trees = {
    quickshell = ../user/quickshell;
    hypr = ../user/hypr;
    desk = ../user/desk;
  };
  flagged = [
    "quickshell"
    "desk"
  ];

  treeFailures = lib.concatLists (
    lib.mapAttrsToList (
      name: src:
      let
        f = files.${name} or null;
        onChange = if lib.elem name flagged then "deskReloadShell=1" else "";
      in
      if f == null then
        [ "xdg.configFile.${name}: missing" ]
      else
        lib.optional (
          toString f.source != toString src
        ) "xdg.configFile.${name}.source: ${toString f.source}, not ${toString src}"
        ++ lib.optional f.recursive "xdg.configFile.${name}.recursive: true, not one link for the tree"
        ++ lib.optional (
          f.onChange != onChange
        ) "xdg.configFile.${name}.onChange: \"${f.onChange}\", not \"${onChange}\""
    ) trees
  );

  # A file another module puts inside a linked tree would be linked into the
  # read-only store directory, which fails at activation.
  inside = lib.filter (t: lib.any (name: lib.hasPrefix ".config/${name}/" t) (lib.attrNames trees)) (
    lib.mapAttrsToList (_: f: f.target) home.home.file
  );

  activation = home.home.activation;
  reload = activation.deskReloadShell or null;

  failures =
    treeFailures
    ++ map (t: "home.file: ${t} is inside a linked tree") inside
    ++ lib.optional (activation ? deskSync) "home.activation.deskSync: still defined"
    ++ lib.optional (reload == null) "home.activation.deskReloadShell: missing"
    ++ lib.optional (
      reload != null && !(lib.elem "onFilesChange" reload.after)
    ) "home.activation.deskReloadShell: not after onFilesChange"
    ++ lib.optional (lib.any (
      p: lib.getName p == "desk-sync"
    ) home.home.packages) "home.packages: desk-sync still installed";
in
pkgs.runCommand "desk-config-links-tests" { failures = lib.concatLines failures; } ''
  if [ -n "$failures" ]; then
    printf '%s' "$failures" | sed 's/^/FAIL /'
    exit 1
  fi
  touch $out
''

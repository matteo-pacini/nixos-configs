# The fleet panel's helper, `desk-fleet` (protocol: desk-fleet.py).
#
# The host list is this machine, then the hosts it may SSH into
# (lib/ssh-mesh.nix), with each one's kind from lib/host-kinds.nix.
#
# tmux and gh are pinned: tmux runs the actions' private sessions and gh's
# JSON is parsed. ssh and ghostty come from the user's PATH: they are the
# ones the mesh config and the desktop use. comin and comin-deploy are each
# host's own system packages, reached over ssh (or locally here).
{
  lib,
  writers,
  writeText,
  tmux,
  gh,
  self ? "BrightFalls",
  repo ? "matteo-pacini/nixos-configs",
}:
let
  mesh = import ../../../../../lib/ssh-mesh.nix;
  kinds = import ../../../../../lib/host-kinds.nix;
  host = name: {
    label = name;
    alias = mesh.hosts.${name}.principal;
    inherit (kinds.${name}) darwin device;
    local = name == self;
  };
  config = writeText "desk-fleet.json" (
    builtins.toJSON {
      inherit repo;
      hosts = map host ([ self ] ++ mesh.allow.${self});
    }
  );
in
writers.writePython3Bin "desk-fleet"
  {
    flakeIgnore = [
      "E501"
      "W503"
    ];
  }
  (
    builtins.replaceStrings
      [ "@config@" "@tmux@" "@gh@" ]
      [ "${config}" (lib.getExe tmux) (lib.getExe gh) ]
      (builtins.readFile ./desk-fleet.py)
  )

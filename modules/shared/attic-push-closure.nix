# Push one or more store-path closures to the self-hosted attic cache,
# authenticating with the agenix netrc token. Login state goes into a
# throwaway XDG_CONFIG_HOME so no attic client config is left behind.
#
# Shared by the NixOS and Darwin nix-core modules; exposed on hosts
# with custom.nix-core.atticCache wired up.
{ pkgs, netrcFile }:
pkgs.writeShellApplication {
  name = "attic-push-closure";
  runtimeInputs = [
    pkgs.attic-client
    pkgs.gawk
  ];
  text = ''
    if [ "$#" -lt 1 ]; then
      echo "usage: attic-push-closure <store-path>..." >&2
      echo "e.g.:  attic-push-closure /run/current-system" >&2
      exit 64
    fi
    if [ "$(id -u)" -ne 0 ]; then
      echo "must run as root: the attic token is root-readable only" >&2
      exit 1
    fi
    token=$(awk '/^password/ { print $2 }' "${toString netrcFile}")
    XDG_CONFIG_HOME=$(mktemp -d)
    export XDG_CONFIG_HOME
    trap 'rm -rf "$XDG_CONFIG_HOME"' EXIT
    attic login nexus https://cache.matteopacini.me "$token"
    attic push main "$@"
  '';
}

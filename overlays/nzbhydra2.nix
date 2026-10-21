# nzbhydra2 9.1.1 ahead of nixpkgs. nzbhydra2/package.nix is a verbatim copy
# of pkgs/by-name/nz/nzbhydra2/package.nix from the PR head below; update it
# from there if the PR changes. Delete this overlay (and its import in
# flake.nix) once the PR reaches nixos-unstable.
#
# 9.x migrates the H2 database once on first start (2.1 -> 2.4) and keeps the
# old file as nzbhydra.mv.db.old.bak.<ts>, so rolling back to 8.x needs that
# backup restored.
#
# Fix: https://github.com/NixOS/nixpkgs/pull/574030 (head 9d0641e3)
self: super: {
  nzbhydra2 = self.callPackage ./nzbhydra2/package.nix { };
}

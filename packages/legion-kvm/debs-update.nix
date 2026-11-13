# Regenerates the pinned deb closures (no import-from-derivation at eval):
#   nix build --impure -f packages/legion-kvm/debs-update.nix -o debs
#   cp debs/debs-*.nix packages/legion-kvm/
let
  flake = builtins.getFlake (toString ../..);
  inherit (flake.nixosConfigurations.BrightFalls.pkgs) vmTools symlinkJoin fetchurl;
  amd64 = vmTools.debDistros.debian13x86_64 // {
    # libnvidia-egl-gbm1 is in contrib; upstream's Containerfile enables it too.
    packagesLists = vmTools.debDistros.debian13x86_64.packagesLists ++ [
      (fetchurl {
        url = "${vmTools.debDistros.debian13x86_64.urlPrefix}/dists/trixie/contrib/binary-amd64/Packages.xz";
        hash = "sha256-km42URDIOnvJdMJwCoLL2DOkzh6mtBNMl7arqF5ey4Q=";
      })
    ];
  };
  lists = import ./debian-packages.nix;
  closure =
    distro: packages:
    vmTools.debClosureGenerator {
      inherit (distro) name packagesLists urlPrefix;
      inherit packages;
    };
in
symlinkJoin {
  name = "legion-kvm-debs";
  paths = [ ];
  postBuild = ''
    cp ${closure amd64 (amd64.packages ++ lists.amd64)} $out/debs-amd64.nix
    cp ${closure vmTools.debDistros.debian13i386 lists.i386} $out/debs-i386.nix
  '';
}

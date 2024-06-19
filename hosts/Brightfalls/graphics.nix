{ pkgs, ... }:
{
  hardware.opengl = {
    enable = true;
    driSupport = true;
    driSupport32Bit = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
    package = pkgs.unstable.mesa.drivers;
    package32 = pkgs.pkgsi686Linux.unstable.mesa.drivers;
  };

  system.replaceRuntimeDependencies = [
    {
      original = pkgs.mesa;
      replacement = pkgs.unstable.mesa;
    }
  ];
}

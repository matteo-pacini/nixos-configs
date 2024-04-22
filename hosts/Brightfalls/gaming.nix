{
  config,
  pkgs,
  lib,
  ...
}: {
  boot.kernel.sysctl = {
    "vm.max_map_count" = "1048576";
  };

  hardware.steam-hardware.enable = true;

  hardware.opengl = with pkgs; {
    enable = true;
    driSupport = true;
    driSupport32Bit = true;
    package = pkgs.unstable-mesa.drivers;
    package32 = pkgs.pkgsi686Linux.unstable-mesa.drivers;
  };

  programs.steam.enable = true;

  system.replaceRuntimeDependencies = [
    {
      original = pkgs.mesa;
      replacement = pkgs.unstable-mesa;
    }
  ];

  security.polkit.enable = true;

  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if ((action.id == "org.corectrl.helper.init" ||
        action.id == "org.corectrl.helperkiller.init") &&
        subject.local == true &&
        subject.active == true &&
        subject.isInGroup("corectrl")) {
          return polkit.Result.YES;
      }
    });
  '';

  programs.corectrl = {
    enable = true;
    gpuOverclock = {
      enable = true;
      ppfeaturemask = "0xffffffff";
    };
  };
}

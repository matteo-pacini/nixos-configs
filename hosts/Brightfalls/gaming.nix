{ pkgs, ... }:
{
  boot.kernel.sysctl = {
    "vm.max_map_count" = "1048576";
  };

  hardware.steam-hardware.enable = true;

  programs.steam = {
    enable = true;
    extraPackages = with pkgs; [ gamescope ];
  };

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

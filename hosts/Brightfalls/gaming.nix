{
  pkgs,
  lib,
  config,
  ...
}:
{
  boot.kernel.sysctl = {
    "vm.max_map_count" = "1048576";
  };

  hardware.steam-hardware.enable = true;

  programs.steam = {
    enable = true;
    package = pkgs.steam.override {
      extraEnv = {
        # Use integrated GPU (Radeon 780M) for Steam client UI
        # Games can override this via launch options if eGPU is preferred
        DRI_PRIME = "0";
      };
    };
    extraPackages = with pkgs; [
      gamescope
    ];
  };

  services.ananicy = lib.mkIf (config.programs.steam.enable) {
    enable = true;
    package = pkgs.ananicy-cpp;
    rulesProvider = pkgs.ananicy-cpp;
    extraRules = [
      {
        "name" = "gamescope";
        "nice" = -20;
      }
    ];
  };

  services.lact.enable = true;

  programs.gamemode = {
    enable = true;
    enableRenice = true;
    settings = {
      general = {
        renice = 10;
        disable_splitlock = 1;
      };
    };
  };

  hardware.amdgpu.overdrive = {
    enable = true;
    ppfeaturemask = "0xffffffff";
  };

  # Passthrough: run a game on DP-1 only, restoring DP-2 (60Hz) on exit/crash.
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "single-monitor" ''
      gdctl=${pkgs.mutter}/bin/gdctl

      restore() {
        "$gdctl" set \
          --logical-monitor --primary --monitor DP-1 --mode 2560x1440@143.998 \
          --logical-monitor --monitor DP-2 --right-of DP-1 --mode 2560x1440@59.951
      }
      trap restore EXIT

      "$gdctl" set --logical-monitor --primary --monitor DP-1 --mode 2560x1440@143.998

      "$@"
    '')
  ];
}

{
  pkgs,
  lib,
  config,
  ...
}:
let
  displayLayout = pkgs.writeShellApplication {
    name = "display-layout";
    runtimeInputs = with pkgs; [
      coreutils
      hyprland
      jq
    ];
    text = builtins.readFile ./display-layout.sh;
  };
in
{
  boot.kernel.sysctl = {
    "vm.max_map_count" = "1048576";
  };

  hardware.steam-hardware.enable = true;

  # Steam library volume: fresh mkfs.ext4 on reinstall leaves it root-owned
  systemd.tmpfiles.rules = [ "d /mnt/games 0755 matteo users -" ];

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

  custom.legion-kvm = {
    enable = true;
    users = [ "matteo" ];
    # DP-1, the primary monitor (monitors.xml).
    resolution = {
      width = 2560;
      height = 1440;
    };
    refreshRate = 144;
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

  environment.systemPackages = [
    displayLayout
    # Passthrough: run a game on DP-1 only, restoring DP-2 (60Hz) on exit/crash.
    (pkgs.writeShellScriptBin "single-monitor" ''
      exec ${lib.getExe displayLayout} single "$@"
    '')
  ];
}

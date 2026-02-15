{
  pkgs,
  lib,
  config,
  isVM,
  ...
}:
{
  boot.kernel.sysctl = {
    "vm.max_map_count" = "1048576";
  };

  hardware.steam-hardware.enable = pkgs.stdenv.hostPlatform.isx86_64;

  programs.steam = {
    enable = pkgs.stdenv.hostPlatform.isx86_64;
    package = lib.mkIf (!isVM) (
      pkgs.steam.override {
        extraEnv = {
          # Use integrated GPU (Radeon 780M) for Steam client UI
          # Games can override this via launch options if eGPU is preferred
          DRI_PRIME = "0";
        };
      }
    );
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

  services.lact.enable = !isVM;

  programs.gamemode = lib.mkIf (pkgs.stdenv.hostPlatform.isx86_64) {
    enable = true;
    enableRenice = true;
    settings = {
      general = {
        renice = 10;
        disable_splitlock = 1;
      };
    };
  };

  hardware.amdgpu.overdrive = lib.mkIf (!isVM) {
    enable = true;
    ppfeaturemask = "0xffffffff";
  };

  services.sunshine = lib.mkIf (!isVM) {
    enable = true;
    openFirewall = true;
    autoStart = true;
    capSysAdmin = true;
    applications = {
      apps = [
        {
          name = "Desktop";
          image-path = "desktop.png";
        }
      ];
    };
    settings = {
      sunshine_name = "BrightFalls Sunshine";
      global_prep_cmd = builtins.toJSON [
        {
          # Switch to HDMI for streaming (e.g., TV via capture card)
          do = "${pkgs.mutter}/bin/gdctl set --logical-monitor --primary --monitor HDMI-1 --mode 3840x2160@59.940";
          # Restore dual DP monitors when streaming ends
          undo = "${pkgs.mutter}/bin/gdctl set --logical-monitor --primary --monitor DP-1 --mode 2560x1440@143.998 --logical-monitor --monitor DP-2 --right-of DP-1 --mode 2560x1440@59.951";
        }
      ];
      audio_sink = "alsa_output.usb-Schiit_Audio_USB_Modi_Device-00.analog-stereo";
      fec_percentage = 10;
      qp = 10;
    };
  };

}

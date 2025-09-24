{ pkgs, ... }:
{
  boot.kernel.sysctl = {
    "vm.max_map_count" = "1048576";
  };

  hardware.steam-hardware.enable = true;

  programs.steam = {
    enable = true;
    extraPackages = with pkgs; [
      gamescope
      (
        with pkgs;
        writeShellScriptBin "amdvlk-run" ''
          export VK_DRIVER_FILES="${amdvlk}/share/vulkan/icd.d/amd_icd64.json:${pkgsi686Linux.amdvlk}/share/vulkan/icd.d/amd_icd32.json"
          exec "$@"
        ''
      )
      (
        with pkgs;
        writeShellScriptBin "radv-run" ''
          export VK_DRIVER_FILES="${mesa}/share/vulkan/icd.d/radeon_icd.x86_64.json:${pkgsi686Linux.mesa}/share/vulkan/icd.d/radeon_icd.i686.json"
          exec "$@"
        ''
      )
    ];
  };

  services.ananicy = {
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

  services.sunshine = {
    enable = true;
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
          do = "${pkgs.mutter}/bin/gdctl set --logical-monitor --primary --monitor HDMI-1 --mode 3840x2160@59.940";
          undo = "${pkgs.mutter}/bin/gdctl set --logical-monitor --primary --monitor DP-1 --mode 2560x1440@143.998 --logical-monitor --monitor DP-2 --right-of DP-1 --mode 2560x1440@59.951 --transform 90";
        }
      ];
      audio_sink = "alsa_output.usb-Schiit_Audio_USB_Modi_Device-00.analog-stereo";
      fec_percentage = 10;
      qp = 10;
    };
  };

}

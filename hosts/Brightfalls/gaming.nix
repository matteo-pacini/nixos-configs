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
        {
          name = "Steam";
          output = "steam.txt";
          detached = [
            "/run/wrappers/bin/sudo -u matteo ${pkgs.util-linux}/bin/setsid env PULSE_SERVER=unix:/run/user/1000/pulse/native XDG_RUNTIME_DIR=/run/user/1000 ${pkgs.steam}/bin/steam steam://open/gamepadui"
          ];
          exclude-global-prep-cmd = "false";
          auto-detach = "true";
          image-path = "steam.png";
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

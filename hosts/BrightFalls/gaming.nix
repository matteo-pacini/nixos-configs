{
  pkgs,
  lib,
  config,
  ...
}:
let
  # Sunshine's base port; the video stream is on port + 9.
  sunshinePort = 47989;
  displayLayout = pkgs.writeShellApplication {
    name = "display-layout";
    runtimeInputs = with pkgs; [
      coreutils
      hyprland
      iproute2
      jq
      systemd
    ];
    text = ''
      gdctl=${lib.optionalString config.services.desktopManager.gnome.enable "${pkgs.mutter}/bin/gdctl"}
      video_port=${toString (sunshinePort + 9)}
    ''
    + builtins.readFile ./display-layout.sh;
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

  services.sunshine = {
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
      port = sunshinePort;
      # With no capture method set, Sunshine also probes the XDG portal at
      # every start, which raises GNOME's remote-control dialog at each login.
      capture = "kms";
      # Stream from the 4K dummy plug on HDMI alone, then restore the dual DP
      # monitors; display-layout.sh has the layers that restore them when
      # the undo never runs.
      global_prep_cmd = builtins.toJSON [
        {
          do = "${lib.getExe displayLayout} stream-on";
          undo = "${lib.getExe displayLayout} restore";
        }
      ];
      audio_sink = "alsa_output.usb-Schiit_Audio_USB_Modi_Device-00.iec958-stereo";
      fec_percentage = 10;
      qp = 10;
    };
  };
}

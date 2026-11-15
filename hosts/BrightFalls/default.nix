{
  config,
  pkgs,
  ...
}:
{
  imports = [
    ./networking.nix
    ./users.nix
    ./desktop.nix
    ./desktop-hyprland.nix
    ./audio
    ./services.nix
    ./graphics.nix
    ./gaming.nix
    ./hardware.nix
    ./boot-splash.nix
    ./printer.nix
    ./virtualization.nix
    ./specialisations.nix
  ];

  custom.kernel.enable = true;

  custom.nix-core = {
    enable = true;
    # Offload per command: nom build --builders @/etc/nix/machines -j0 ...
    nexusBuilder = {
      enable = true;
      sshKey = "/home/matteo/.ssh/mesh";
    };
    nightspringsBuilder = {
      enable = true;
      sshKey = "/home/matteo/.ssh/mesh";
    };
    trustedUsers = [
      "matteo"
      "root"
    ];
    # Substituter + auth for pulling from the private attic cache
    atticCache = {
      enable = true;
      netrcFile = config.age.secrets."brightfalls/attic-netrc".path;
    };
  };

  # Boot loader
  boot.loader.systemd-boot = {
    enable = true;
    editor = false; # no console kernel-cmdline editing
    memtest86.enable = pkgs.stdenv.hostPlatform.isx86;
    configurationLimit = 5;
  };
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.timeout = 30;
  # /tmp is on the root disk, not tmpfs; tmpfiles' 10d age rule alone lets it grow to 20G+.
  boot.tmp.cleanOnBoot = true;

  # System Packages

  environment.systemPackages = with pkgs; [
    sshfs
  ];

  # Force-installs the Claude in Chrome extension into Chromium. Chromium
  # reads managed policy only from compiled-in /etc paths, so this cannot
  # live next to custom.claude-code.chrome.enable in Home Manager.
  programs.chromium = {
    enable = true;
    extensions = [ "fcoeoabgfenejglbffodgkkbkcdhcgfn" ];
  };

  custom.locale.enable = true;
  custom.bluetooth.enable = true;
  custom.fonts.enable = true;
  custom.nix-index.enable = true;

  custom.autoDeploy = {
    enable = true;
    confirm = true;
  };
  # comin's own user service; notifies when a staged deployment needs a reboot.
  services.comin.desktop.enable = true;
  # `comin desktop` panics unless its first notification is delivered, and
  # graphical-session.target starts it before the shell owns the
  # notification name. It also exits 1 whenever comin's event stream drops
  # (comin restarts itself after deploying its own unit); each restart
  # notifies once, so the start limit caps that at six in two minutes.
  systemd.user.services.comin-desktop = {
    after = [ "quickshell.service" ];
    startLimitIntervalSec = 120;
    startLimitBurst = 6;
    serviceConfig = {
      ExecStartPre = "${pkgs.glib.bin}/bin/gdbus wait --session --timeout 60 org.freedesktop.Notifications";
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };

  system.stateVersion = "26.05";
}

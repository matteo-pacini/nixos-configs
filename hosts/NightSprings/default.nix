{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
  ];

  users.users."matteo" = {
    home = "/Users/matteo";
  };

  programs.zsh.enable = true;

  security.pam.enableSudoTouchIdAuth = true;

  services.nix-daemon.enable = true;

  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = ["nix-command" "flakes"];
  nix.gc.automatic = true;

  homebrew = {
    enable = true;
    onActivation.cleanup = "zap";
    casks = [
      "1password"
      "firefox"
      "zoom"
      "slack"
      "mullvadvpn"
      "dash"
      "telegram"
      "whatsapp"
    ];
    masApps = {
    };
  };

  system.stateVersion = 4;

  nixpkgs.hostPlatform = "aarch64-darwin";
}

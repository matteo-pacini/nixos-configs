{pkgs, ...}: {
  imports = [
    ./homebrew.nix
    ./fonts.nix
  ];

  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = ["nix-command" "flakes"];
  nix.gc.automatic = true;
  services.nix-daemon.enable = true;

  environment.systemPackages = with pkgs; [
  ];

  users.users."matteo" = {
    home = "/Users/matteo";
  };

  system.defaults.NSGlobalDomain.AppleInterfaceStyle = "Dark";
  system.defaults.dock.magnification = true;
  system.defaults.dock.show-recents = false;
  system.defaults.finder.AppleShowAllExtensions = true;

  programs.zsh.enable = true;

  security.pam.enableSudoTouchIdAuth = true;

  system.stateVersion = 4;

  nixpkgs.hostPlatform = "aarch64-darwin";
}

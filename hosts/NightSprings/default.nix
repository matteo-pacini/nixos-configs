{ pkgs, ... }:
{
  imports = [
    ./fonts.nix
    ./system.nix
  ];

  nixpkgs.config.allowUnfree = true;

  nix = {
    settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
    settings.trusted-users = [ "@matteo" ];
    extraOptions = ''
      extra-platforms = x86_64-darwin aarch64-darwin
    '';
  };

  services.nix-daemon.enable = true;

  environment.systemPackages = [ pkgs.nix-output-monitor ];

  users.users."matteo" = {
    home = "/Users/matteo";
  };

  programs.zsh.enable = true;

  system.stateVersion = 4;

  nixpkgs.hostPlatform = "aarch64-darwin";
}

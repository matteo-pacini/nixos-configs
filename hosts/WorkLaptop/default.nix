{ pkgs, ... }:
{
  imports = [
    ./fonts.nix
    ./system.nix
    ../shared/darwin/yabai.nix
  ];

  nixpkgs.config.allowUnfree = true;

  nix = {
    settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
    settings.trusted-users = [ "@admin" ];
    extraOptions = ''
      extra-platforms = x86_64-darwin aarch64-darwin
    '';
  };

  services.nix-daemon.enable = true;

  environment.systemPackages = with pkgs; [ ];

  users.users."admin" = {
    home = "/Users/admin";
  };

  programs.zsh.enable = true;

  system.stateVersion = 4;

  nixpkgs.hostPlatform = "aarch64-darwin";
}

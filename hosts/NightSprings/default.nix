{ pkgs, ... }:
{
  imports = [
    ./fonts.nix
    ./system.nix
  ];

  nixpkgs.config.allowUnfree = true;

  nix = {
    extraOptions = ''
      extra-platforms = x86_64-darwin aarch64-darwin
    '';
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [ "matteo" ];
      substituters = [
        "http://192.168.7.7:8080/darwin"
      ];
      trusted-public-keys = [
        "darwin:OayisVmwq18dibr9PDU5g6FROl9IGxxmNF/wlWncLgY="
      ];
    };
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

{
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    ./hardware.nix
    ./networking.nix
    ./users.nix
    ./desktop.nix
    ./audio.nix
    ./services.nix
    ./gaming.nix
    ./printer.nix
    ./iphone.nix
  ];

  custom.kernel.enable = true;
  custom.bluetooth.enable = true;
  custom.fonts.enable = true;

  environment.systemPackages = with pkgs; [ sshfs ];

  custom.nix-core = {
    enable = true;
    trustedUsers = [
      "debora"
      "root"
    ];
  };

  custom.locale = {
    enable = true;
    consoleKeyMap = "uk";
  };

  system.stateVersion = "25.11";
}

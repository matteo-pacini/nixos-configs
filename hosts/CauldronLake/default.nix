{
  config,
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
  custom.nix-index.enable = true;

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

  custom.autoDeploy = {
    enable = true;
    telegramEnvFile = config.age.secrets."nexus/janitor.env".path;
    telegramPrefix = "[CauldronLake] ";
    notifyStaged = true;
  };
  # comin's own user service; notifies when a staged deployment needs a reboot.
  services.comin.desktop.enable = true;

  system.stateVersion = "26.05";
}

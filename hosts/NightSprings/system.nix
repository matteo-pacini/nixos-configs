{ ... }:
{
  custom.system-defaults.enable = true;

  custom.sshMesh = {
    enable = true;
    host = "NightSprings";
  };

  services.tailscale.enable = true;

  homebrew = {
    enable = true;
    global = {
      autoUpdate = false;
    };
    onActivation = {
      autoUpdate = true;
      upgrade = true;
    };
    casks = [
      "1password"
      "mullvadvpn"
      "dash"
      "telegram"
      "whatsapp"
      "sf-symbols"
      "vlc"
    ];
  };
}

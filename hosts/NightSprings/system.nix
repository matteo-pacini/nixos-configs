{ ... }:
{
  custom.system-defaults.enable = true;

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

{ ... }:
{
  custom.system-defaults.enable = true;

  custom.sshMesh = {
    enable = true;
    host = "NightSprings";
  };

  custom.xcode = {
    enable = true;
    versions = [ "27.0" ];
    active = "27.0";
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

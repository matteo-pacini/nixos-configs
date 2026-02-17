{ pkgs, ... }:
{
  custom.system-defaults.enable = true;

  services.tailscale.enable = true;
  services.tailscale.package = pkgs.tailscale.overrideAttrs (oldAttrs: {
    doCheck = false;
  });

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
      "element"
      "telegram"
      "whatsapp"
      "jellyfin-media-player"
      "sf-symbols"
      "vlc"
    ];
  };
}

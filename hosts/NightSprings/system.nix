{ pkgs, ... }:
{
  system.defaults.NSGlobalDomain.AppleInterfaceStyle = "Dark";
  system.defaults.dock.magnification = true;
  system.defaults.dock.show-recents = false;

  system.defaults.finder.CreateDesktop = true;
  system.defaults.finder.AppleShowAllExtensions = true;

  security.pam.services.sudo_local.touchIdAuth = true;

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
      "telegram"
      "whatsapp"
      "jellyfin-media-player"
      "sf-symbols"
      "vlc"
    ];
  };
}

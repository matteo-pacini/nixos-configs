{ pkgs, ... }:
{
  system.defaults.NSGlobalDomain.AppleInterfaceStyle = "Dark";
  system.defaults.dock.magnification = false;
  system.defaults.dock.show-recents = false;

  system.defaults.dock.autohide = true;
  system.defaults.dock.autohide-time-modifier = 0.0;
  system.defaults.dock.autohide-delay = 0.0;

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
      "microsoft-teams"
      "microsoft-outlook"
      "slack"
      "sf-symbols"
      "figma"
      "jellyfin-media-player"
    ];
  };

}

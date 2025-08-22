{ ... }:
{
  system.defaults.NSGlobalDomain.AppleInterfaceStyle = "Dark";
  system.defaults.dock.magnification = true;
  system.defaults.dock.show-recents = false;

  system.defaults.finder.CreateDesktop = true;
  system.defaults.finder.AppleShowAllExtensions = true;

  security.pam.services.sudo_local.touchIdAuth = true;

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
      "xcodes"
      "android-studio"
    ];
  };
}

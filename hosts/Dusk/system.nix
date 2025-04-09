{ pkgs, ... }:
{
  system.defaults.NSGlobalDomain.AppleInterfaceStyle = "Dark";
  system.defaults.dock.magnification = true;
  system.defaults.dock.show-recents = false;

  system.defaults.finder.CreateDesktop = true;
  system.defaults.finder.AppleShowAllExtensions = true;

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
      "iterm2"
    ];
  };
}

{ ... }:
{
  custom.system-defaults.enable = true;

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
      "xcodes-app"
      "android-studio"
    ];
  };
}

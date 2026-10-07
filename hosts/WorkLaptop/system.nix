{ ... }:
{
  custom.system-defaults.enable = true;

  custom.sshMesh = {
    enable = true;
    host = "WorkLaptop";
  };

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

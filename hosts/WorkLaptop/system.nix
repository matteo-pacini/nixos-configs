{ ... }:
{
  custom.system-defaults.enable = true;

  custom.sshMesh = {
    enable = true;
    host = "WorkLaptop";
  };

  custom.xcode = {
    enable = true;
    versions = [ "27.0" ];
    active = "27.0";
    # CrowdStrike Falcon flags root-run xcodebuild license/first-launch setup.
    firstLaunch = false;
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
      "android-studio"
    ];
  };
}

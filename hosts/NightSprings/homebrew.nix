{pkgs, ...}: {
  homebrew = {
    enable = true;
    onActivation.cleanup = "zap";
    casks = [
      "1password"
      "firefox"
      "zoom"
      "slack"
      "mullvadvpn"
      "dash"
      "telegram"
      "whatsapp"
      "google-chrome"
      "secretive"
    ];
    masApps = {
    };
  };
}

{pkgs, ...}: {
  homebrew = {
    enable = true;
    onActivation.cleanup = "zap";
    onActivation.upgrade = true;
    onActivation.autoUpdate = true;
    casks = [
      "1password"
      "firefox"
      "mullvadvpn"
      "dash"
      "telegram"
      "whatsapp"
      "microsoft-teams"
      "utm"
      "zerotier-one"
    ];
    masApps = {
    };
  };
}

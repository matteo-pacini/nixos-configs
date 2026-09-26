{ pkgs, ... }:
{
  # Animated snowflake splash in stage 1. Plymouth also owns the LUKS prompt
  # (systemd-ask-password-plymouth); the SSH unlock agent on :2222 answers the
  # same request and dismisses it. Esc toggles the text log during boot.
  boot.plymouth = {
    enable = true;
    theme = "brightfalls";
    themePackages = [ pkgs.plymouth-brightfalls ];
    # Copied into the initrd; brightfalls.script draws the prompt with it.
    font = "${pkgs.jetbrains-mono}/share/fonts/truetype/JetBrainsMono-Regular.ttf";
  };

  # Keep kernel and udev chatter from drawing over the splash.
  boot.consoleLogLevel = 3;
  boot.initrd.verbose = false;
  boot.kernelParams = [
    "quiet"
    "rd.udev.log_level=3"
    "udev.log_priority=3"
  ];
}

{
  config,
  lib,
  pkgs,
  ...
}:
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

  # The theme is laid out for 1440p. Without amdgpu in stage 1, Plymouth draws
  # on the firmware framebuffer, which this firmware leaves at 800x600.
  hardware.amdgpu.initrd.enable = true;
  # amdgpu now probes in stage 1, so the drm.edid_firmware blobs from
  # hardware.display must be in the initrd too; the modules closure only
  # copies firmware amdgpu itself declares.
  boot.initrd.extraFirmwarePaths = map (o: "edid/${o.edid}") (
    lib.filter (o: o.edid != null) (lib.attrValues config.hardware.display.outputs)
  );

  # Keep kernel and udev chatter from drawing over the splash.
  boot.consoleLogLevel = 3;
  boot.initrd.verbose = false;
  boot.kernelParams = [
    "quiet"
    "rd.udev.log_level=3"
    "udev.log_priority=3"
  ];

  # Sunshine picks its capture backend once, at startup. If that is while
  # Plymouth is still handing the display to GDM, its KMS probe finds no
  # active planes and it falls back to the XDG portal, which asks for remote
  # control on every encoder probe. Start it once the handoff is done.
  systemd.user.services.sunshine.serviceConfig.ExecStartPre =
    pkgs.writeShellScript "wait-for-plymouth-quit" ''
      while [ "$(${pkgs.systemd}/bin/systemctl show --property=ActiveState --value plymouth-quit-wait.service)" = activating ]; do
        sleep 0.5
      done
    '';
}

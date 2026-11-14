# Hyprland as a second GDM session beside GNOME. GNOME stays the default
# and the autologin session.
{ ... }:
{
  programs.hyprland = {
    enable = true;
    withUWSM = true;
  };

  # With no default, GDM autologs into the session the user last picked, so one
  # Hyprland login would make every later boot autologin into Hyprland. Setting
  # it makes GDM reset every user's saved session to GNOME each time it starts.
  services.displayManager.defaultSession = "gnome";

  # Stable card-node names for AQ_DRM_DEVICES, which is colon-separated and so
  # cannot take /dev/dri/by-path names. Card numbers are not stable across boots.
  services.udev.extraRules = ''
    SUBSYSTEM=="drm", KERNEL=="card*", ENV{DEVTYPE}=="drm_minor", KERNELS=="0000:07:00.0", SYMLINK+="dri/dgpu"
    SUBSYSTEM=="drm", KERNEL=="card*", ENV{DEVTYPE}=="drm_minor", KERNELS=="0000:0a:00.0", SYMLINK+="dri/igpu"
  '';

  # The eGPU never comes back from sleep. Under GNOME, gsd-media-keys holds the
  # handle-suspend-key inhibitor and these settings are not consulted; without
  # it (Hyprland), logind would suspend on KEY_SLEEP, which the keyboards and
  # mouse advertise, and hibernate on a long press of it.
  services.logind.settings.Login = {
    HandleSuspendKey = "ignore";
    HandleSuspendKeyLongPress = "ignore";
  };
}

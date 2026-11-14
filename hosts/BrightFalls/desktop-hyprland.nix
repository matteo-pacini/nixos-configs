# Hyprland as a second GDM session beside GNOME. GNOME stays the default
# and the autologin session.
{ lib, pkgs, ... }:
{
  programs.hyprland = {
    enable = true;
    withUWSM = true;
    # Everything here assumes the UWSM session, so GDM must not offer the plain
    # hyprland.desktop. It stays installed, with NoDisplay (GDM skips it), not
    # Hidden or removed: hyprland-uwsm.desktop execs `uwsm start …
    # hyprland.desktop`, which looks the entry up under
    # $XDG_DATA_DIRS/wayland-sessions and rejects Hidden entries.
    # A symlinkJoin, not overrideAttrs, so Hyprland is not rebuilt from source.
    # makeOverridable because the module's package apply calls .override.
    package = lib.makeOverridable (
      args:
      let
        hyprland = pkgs.hyprland.override args;
      in
      pkgs.symlinkJoin {
        inherit (hyprland)
          name
          version
          passthru
          ;
        # The join has only `out`, so the man output goes in it rather than in
        # outputsToInstall.
        meta = removeAttrs hyprland.meta [ "outputsToInstall" ];
        paths = [
          hyprland
          hyprland.man
        ];
        postBuild = ''
          entry=$out/share/wayland-sessions/hyprland.desktop
          rm "$entry"
          sed '/^\[Desktop Entry\]$/a NoDisplay=true' \
            ${hyprland}/share/wayland-sessions/hyprland.desktop > "$entry"
        '';
      }
    ) { };
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

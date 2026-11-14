# Hyprland as a second GDM session beside GNOME. GNOME stays the default
# and the autologin session.
{
  config,
  options,
  lib,
  pkgs,
  ...
}:
let
  repo = toString ../..;
  # The repo files that define an option, relative to the repo root.
  setIn =
    option:
    lib.concatStringsSep ", " (
      map (lib.removePrefix "${repo}/") (lib.filter (lib.hasPrefix "${repo}/") (map toString option.files))
    );
  net = config.networking;
  wolInterfaces = lib.attrNames (lib.filterAttrs (_: i: i.wakeOnLan.enable) net.interfaces);

  # The network panel's "Set in Nix" rows (user/quickshell/Network.qml). A
  # row is present only while its setting has the value it states.
  lockedRows =
    lib.optional config.services.tailscale.enable {
      id = "tailscale";
      label = "Tailscale enabled";
      file = setIn options.services.tailscale.enable;
    }
    ++ lib.optional (!net.enableIPv6) {
      id = "ipv6";
      label = "IPv6 off";
      file = setIn options.networking.enableIPv6;
    }
    ++ lib.optional (wolInterfaces != [ ]) {
      id = "wol";
      label = "Wake-on-LAN on ${lib.concatStringsSep ", " wolInterfaces}";
      file = setIn options.networking.interfaces;
    }
    ++ lib.optional (net.hostName != "") {
      id = "hostname";
      label = "Hostname ${net.hostName}";
      file = setIn options.networking.hostName;
    }
    ++ lib.optional net.firewall.enable {
      id = "firewall";
      label = "Firewall on";
      file = setIn options.networking.firewall.enable;
    };
in
{
  home-manager.users.matteo.xdg.dataFile."desk/network/locked.json".text = builtins.toJSON lockedRows;

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

  # font_ui in the desktop palette (users/matteo/hyprland/user/desk/theme.json).
  custom.fonts.extraPackages = [ pkgs.fira-sans ];

  # Stable card-node names for AQ_DRM_DEVICES, which is colon-separated and so
  # cannot take /dev/dri/by-path names. Card numbers are not stable across boots.
  services.udev.extraRules = ''
    SUBSYSTEM=="drm", KERNEL=="card*", ENV{DEVTYPE}=="drm_minor", KERNELS=="0000:07:00.0", SYMLINK+="dri/dgpu"
    SUBSYSTEM=="drm", KERNEL=="card*", ENV{DEVTYPE}=="drm_minor", KERNELS=="0000:0a:00.0", SYMLINK+="dri/igpu"
  '';

  # Under GNOME, gsd-media-keys holds the handle-suspend-key and
  # handle-power-key inhibitors and these settings are not consulted. Without
  # them (Hyprland), logind would act on the keys itself. The eGPU never comes
  # back from sleep, so it must not suspend on KEY_SLEEP, which the keyboards
  # and mouse advertise, or hibernate on a long press of it. A short press of
  # the power key opens the session menu (Quickshell) instead of powering off;
  # a long press still powers off.
  services.logind.settings.Login = {
    HandleSuspendKey = "ignore";
    HandleSuspendKeyLongPress = "ignore";
    HandlePowerKey = "ignore";
    HandlePowerKeyLongPress = "poweroff";
  };
}

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
      map (lib.removePrefix "${repo}/") (
        lib.filter (lib.hasPrefix "${repo}/") (map toString option.files)
      )
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

  pw = config.services.pipewire;
  # Repo files whose definition of `option` satisfies `pred`, for options
  # such as extraConfig that several files add to. A module imported as a
  # directory is reported as the directory.
  definedIn =
    option: pred:
    let
      file =
        d: toString d.file + lib.optionalString (lib.pathIsDirectory (toString d.file)) "/default.nix";
    in
    lib.concatStringsSep ", " (
      map (d: lib.removePrefix "${repo}/" (file d)) (
        lib.filter (
          d: lib.hasPrefix "${repo}/" (toString d.file) && lib.isAttrs d.value && pred d.value
        ) option.definitionsWithLocations
      )
    );
  dropIns = lib.filter lib.isAttrs (lib.attrValues pw.extraConfig.pipewire);
  # A context property from the pipewire.conf drop-ins, or null.
  pwProperty =
    key: lib.findFirst (v: v != null) null (map (c: c."context.properties".${key} or null) dropIns);
  pwFile =
    key:
    definedIn options.services.pipewire.extraConfig.pipewire (
      v: lib.any (c: lib.isAttrs c && c ? "context.properties".${key}) (lib.attrValues v)
    );
  alsaRules = lib.concatMap (c: c."monitor.alsa.rules" or [ ]) (
    lib.filter lib.isAttrs (lib.attrValues pw.wireplumber.extraConfig)
  );
  # A WirePlumber node.name match: "~" starts a regex.
  matchesName =
    name: pattern:
    if lib.hasPrefix "~" pattern then
      builtins.match (lib.removePrefix "~" pattern) name != null
    else
      pattern == name;
  # The update-props WirePlumber gives the node called `name`.
  propsFor =
    name:
    lib.foldl' (acc: r: acc // (r.actions."update-props" or { })) { } (
      lib.filter (r: lib.any (m: m ? "node.name" && matchesName name m."node.name") r.matches) alsaRules
    );
  wpFile =
    key:
    definedIn options.services.pipewire.wireplumber.extraConfig (
      v:
      lib.any (
        c:
        lib.isAttrs c
        && lib.any (r: r.actions."update-props" or { } ? ${key}) (c."monitor.alsa.rules" or [ ])
      ) (lib.attrValues v)
    );
  # 44100 -> "44.1", 96000 -> "96".
  khz =
    rate:
    let
      tenths = rate / 100 - rate / 1000 * 10;
    in
    toString (rate / 1000) + lib.optionalString (tenths != 0) ".${toString tenths}";
  rates =
    let
      allowed = pwProperty "default.clock.allowed-rates";
    in
    if allowed == null then [ ] else lib.sort lib.lessThan allowed;
  minQuantum = pwProperty "default.clock.min-quantum";
  quality = pwProperty "resample.quality";
  # Node names as ALSA gives them, to find the rules that apply.
  modi = propsFor "alsa_output.usb-Schiit_Audio_USB_Modi_Device-00.analog-stereo";
  blue = propsFor "alsa_input.usb-Generic_Blue_Microphones-00.analog-stereo";

  # The audio panel's "Set in Nix" rows (user/quickshell/Audio.qml), on the
  # same terms as the network panel's.
  audioRows =
    # With no default.clock.rate the graph takes the first stream's rate.
    lib.optional (lib.length rates > 1 && pwProperty "default.clock.rate" == null) {
      id = "rates";
      label = "Rates ${khz (lib.head rates)} to ${khz (lib.last rates)} kHz, following the program";
      file = pwFile "default.clock.allowed-rates";
    }
    ++ lib.optional (lib.hasPrefix "S24" (modi."audio.format" or "")) {
      id = "format";
      label = "Modi opened as 24 bit";
      file = wpFile "audio.format";
    }
    # resample.quality in pipewire.conf reaches the daemon's own nodes, not
    # the streams of clients, which resample with their client.conf's.
    ++ lib.optional (minQuantum != null) {
      id = "buffer";
      label =
        "Buffer ${toString minQuantum} frames"
        + lib.optionalString (quality != null) " · daemon resampler quality ${toString quality}";
      file = pwFile "default.clock.min-quantum";
    }
    # ALSA inputs get 2000 plus their profile's priority (2009 and 2109 here).
    ++ lib.optional ((blue."priority.session" or 0) >= 3000) {
      id = "input";
      label = "Blue Microphones ranked first among inputs";
      file = wpFile "priority.session";
    };

  # The system panel's Nix-set values (user/quickshell/System.qml), on the
  # same terms. `khz` is the cap the panel compares with the chip's maximum.
  cpuMax = config.powerManagement.cpufreq.max;
  systemRows =
    lib.optional (cpuMax != null) {
      id = "cpu-max";
      label = "CPU clock limit";
      khz = cpuMax;
      file = setIn options.powerManagement.cpufreq.max;
    }
    # Only the daemon is declared; its fan curve lives in /etc/lact/config.yaml,
    # written by LACT itself.
    ++ lib.optional config.services.lact.enable {
      id = "lact";
      label = "LACT daemon enabled";
      file = setIn options.services.lact.enable;
    };
in
{
  home-manager.users.matteo.xdg.dataFile."desk/network/locked.json".text = builtins.toJSON lockedRows;
  home-manager.users.matteo.xdg.dataFile."desk/audio/locked.json".text = builtins.toJSON audioRows;
  home-manager.users.matteo.xdg.dataFile."desk/system/locked.json".text = builtins.toJSON systemRows;

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

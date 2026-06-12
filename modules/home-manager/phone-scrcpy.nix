{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.phone.scrcpy;

  # Wireless debugging randomizes its port per session, so resolve the
  # phone's address via mDNS on every launch instead of hardcoding it.
  phone-mirror = pkgs.writeShellScriptBin "phone-mirror" ''
    set -u
    export PATH=${
      lib.makeBinPath [
        pkgs.avahi
        pkgs.android-tools
        pkgs.scrcpy
        pkgs.libnotify
        pkgs.gawk
      ]
    }:$PATH

    ADDR=$(avahi-browse -rpt _adb-tls-connect._tcp 2>/dev/null \
      | awk -F';' '/^=/ && $3=="IPv4" {print $8":"$9; exit}')

    if [ -z "$ADDR" ]; then
      notify-send "Phone mirror" "Phone not found — enable Wireless debugging"
      exit 1
    fi

    adb connect "$ADDR" >/dev/null
    exec scrcpy -s "$ADDR" \
      --turn-screen-off \
      --stay-awake \
      --power-off-on-close \
      --window-title "Phone"
  '';
in
{
  options.custom.phone.scrcpy = {
    enable = lib.mkEnableOption "scrcpy phone mirroring with mDNS discovery";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      phone-mirror
      pkgs.scrcpy
      pkgs.android-tools
    ];

    xdg.desktopEntries.phone-mirror = {
      name = "Phone Mirror";
      comment = "Mirror the phone via scrcpy";
      exec = "phone-mirror";
      icon = "phone";
      terminal = false;
      categories = [ "Utility" ];
    };
  };
}

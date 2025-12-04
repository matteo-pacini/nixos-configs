{
  pkgs,
  config,
  ...
}:
let
  envFile = config.age.secrets."nexus/janitor.env".path;
  mdadmNotify = pkgs.writeShellScriptBin "mdadm-notify" ''
    set -euo pipefail
    export TELEGRAM_ENV_FILE="${envFile}"

    EVENT="$1"
    DEVICE="''${2:-unknown}"
    COMPONENT="''${3:-}"

    if [[ -n "$COMPONENT" ]]; then
      MESSAGE="🚨 RAID Alert: $EVENT on $DEVICE (component: $COMPONENT)"
    else
      MESSAGE="🚨 RAID Alert: $EVENT on $DEVICE"
    fi

    ${pkgs.telegram-notify}/bin/telegram-notify "$MESSAGE"
  '';
in
{
  boot.swraid = {
    enable = true;
    mdadmConf = ''
      ARRAY /dev/md/array metadata=1.2 name=nixos:array UUID=ea2caefe:f8f04158:af8eacaa:8b5984b4
      PROGRAM ${mdadmNotify}/bin/mdadm-notify
    '';
  };
}

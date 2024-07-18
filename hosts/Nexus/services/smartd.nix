{ pkgs, config, ... }:
{
  services.smartd =
    let
      mailer = pkgs.writeShellScriptBin "janitor_tell_smartd" ''
        source ${config.age.secrets."nexus/janitor.env".path}

        read -r -d ''' MESSAGE << EOF
        *SMARTD Alert*

        *Subject:* $SMARTD_SUBJECT
        *Device:* $SMARTD_DEVICE ($SMARTD_DEVICETYPE)
        *First Detected:* $SMARTD_TFIRST
        *Failure Type:* $SMARTD_FAILTYPE
        *Message:* $SMARTD_MESSAGE

        This message was generated by smartd.
        EOF

        # Send the message to Telegram
        ${pkgs.curl}/bin/curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
          --data chat_id="$CHANNEL_ID" \
          --data parse_mode="Markdown" \
          --data-urlencode "text=''${MESSAGE}"
      '';
    in
    {
      enable = true;
      notifications = {
        mail = {
          enable = true;
          recipient = "root";
          sender = "smartd@Nexus";
          mailer = "${mailer}/bin/janitor_tell_smartd";
        };
      };
    };
}
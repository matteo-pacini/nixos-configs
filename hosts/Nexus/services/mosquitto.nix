{
  services.mosquitto = {
    enable = true;
    persistence = true;
    settings = {
      autosave_interval = 30;
      autosave_on_changes = false;
    };
    listeners = [
      # Localhost access without auth
      {
        address = "127.0.0.1";
        port = 1883;
        acl = [ "pattern readwrite #" ];
        omitPasswordAuth = true;
        settings.allow_anonymous = true;
      }
      # LAN access without auth (for BrightFalls)
      {
        address = "192.168.10.14";
        port = 1883;
        acl = [ "pattern readwrite pc/brightfalls/#" ];
        omitPasswordAuth = true;
        settings.allow_anonymous = true;
      }
    ];
  };
}

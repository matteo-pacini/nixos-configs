{ ... }:
{
  services.mosquitto = {
    enable = true;
    persistence = true;
    settings = {
      autosave_interval = 30;
      autosave_on_changes = false;
    };
  };
}

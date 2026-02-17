{ ... }:
{
  services.atuin = {
    enable = true;
    openRegistration = true;
    openFirewall = true;
    host = "0.0.0.0";
    port = 8888;
    database.createLocally = true;
  };
}

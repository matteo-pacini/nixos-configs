{ ... }:

{
  users.users."nzbget" = {
    extraGroups = [ "downloads" ];
  };

  services.nzbget = {
    enable = true;
    group = "downloads";
  };
}

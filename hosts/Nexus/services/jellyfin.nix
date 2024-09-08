{ ... }:

{
  users.users."jellyfin" = {
    extraGroups = [ "media" ];
  };

  services.jellyfin = {
    enable = true;
    group = "media";
  };
}

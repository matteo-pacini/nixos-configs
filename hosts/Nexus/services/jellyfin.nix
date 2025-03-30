{ pkgs, ... }:
{
  users.users."jellyfin" = {
    extraGroups = [ "media" ];
  };

  services.jellyfin = {
    enable = true;
    package = pkgs.jellyfin;
    group = "media";
  };
}

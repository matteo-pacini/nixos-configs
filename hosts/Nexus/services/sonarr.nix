{ ... }:

{

  users.users."sonarr" = {
    extraGroups = [
      "media"
      "downloads"
    ];
  };

  services.sonarr = {
    enable = true;
    group = "media";
  };
}

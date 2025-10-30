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
    openFirewall = true; # Direct port access (8989)
  };

}

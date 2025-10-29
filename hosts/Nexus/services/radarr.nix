{ ... }:

{

  users.users."radarr" = {
    extraGroups = [
      "media"
      "downloads"
    ];
  };

  services.radarr = {
    enable = true;
    group = "media";
    openFirewall = true; # Direct port access (7878)
  };
}

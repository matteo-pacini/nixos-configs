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
    # openFirewall = false; # Accessed via nginx reverse proxy only
  };
}

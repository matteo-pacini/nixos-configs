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
    # openFirewall = false; # Accessed via nginx reverse proxy only
  };

  # nixpkgs.config.permittedInsecurePackages = [
  #   "dotnet-sdk-6.0.428"
  #   "aspnetcore-runtime-6.0.36"
  # ];
}

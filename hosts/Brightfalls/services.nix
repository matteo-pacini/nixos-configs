{
  config,
  pkgs,
  ...
}: {
  services.flatpak.enable = true;
  services.fstrim.enable = true;
  virtualisation.docker.enable = true;
  virtualisation.docker.daemon.settings = {
    data-root = "/data/docker";
  };
}

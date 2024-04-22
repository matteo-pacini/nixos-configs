{
  config,
  pkgs,
  ...
}: {
  services.flatpak.enable = true;
  services.fstrim.enable = true;
}

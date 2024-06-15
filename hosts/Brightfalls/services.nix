{
  isVM,
  pkgs,
  lib,
  ...
}:
{
  services.flatpak.enable = true;
  services.fstrim.enable = lib.mkIf (!isVM) true;

  virtualisation.docker = lib.mkIf (!isVM) {
    enable = true;
    daemon = {
      settings = {
        "data-root" = "/data/docker";
      };
    };
  };

  # https://discourse.nixos.org/t/connected-to-mullvadvpn-but-no-internet-connection/35803/8?u=lion
  services.resolved.enable = lib.mkIf (!isVM) true;
  services.mullvad-vpn.enable = lib.mkIf (!isVM) true;
  services.mullvad-vpn.package = pkgs.unstable.mullvad-vpn;
}

{ config, pkgs, ... }:
{
  services.flatpak.enable = true;
  services.fstrim.enable = true;

  # https://discourse.nixos.org/t/connected-to-mullvadvpn-but-no-internet-connection/35803/8?u=lion
  services.resolved.enable = true;
  services.mullvad-vpn.enable = true;
  services.mullvad-vpn.package = pkgs.mullvad-vpn;

  services.thermald.enable = true;
}

{ config, pkgs, ... }:
{
  services.flatpak.enable = true;
  services.fstrim.enable = true;

  # https://discourse.nixos.org/t/connected-to-mullvadvpn-but-no-internet-connection/35803/8?u=lion
  services.resolved.enable = true;
  services.mullvad-vpn.enable = true;
  services.mullvad-vpn.gui.enable = true;

  services.thermald.enable = true;

  custom.sshMesh = {
    enable = true;
    host = "CauldronLake";
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      # NixOS defaults this to true, which lets PAM prompt for a password.
      KbdInteractiveAuthentication = false;
      AllowUsers = [ "matteo" ];
    };
    ports = [ 1788 ];
  };
}

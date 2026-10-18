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

  # Lets matteo hold sleep and lid-switch inhibitors from SSH, e.g.
  # `systemd-inhibit --what=sleep:handle-lid-switch <cmd>`. logind's default
  # policy allows these only from the active local session.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if ((action.id == "org.freedesktop.login1.inhibit-block-sleep" ||
           action.id == "org.freedesktop.login1.inhibit-handle-lid-switch") &&
          subject.user == "matteo") {
        return polkit.Result.YES;
      }
    });
  '';
}

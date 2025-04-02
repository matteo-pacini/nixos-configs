{
  isVM,
  pkgs,
  lib,
  ...
}:
{
  services.fstrim.enable = lib.mkIf (!isVM) true;

  # https://discourse.nixos.org/t/connected-to-mullvadvpn-but-no-internet-connection/35803/8?u=lion
  services.resolved.enable = true;
  services.mullvad-vpn.enable = true;
  services.mullvad-vpn.package = pkgs.mullvad-vpn;

  # Clipboard
  services.spice-vdagentd.enable = lib.mkIf isVM true;

  # Fix service to activate swap at login screen
  systemd.services.fix-swap = {
    description = "Fix Swap Service";

    # Run after the graphical login screen appears
    wantedBy = [ "graphical.target" ];
    after = [ "graphical.target" ];

    # Run only once at startup
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    # The actual command to activate the swap using systemctl
    script = ''
      # Check if swap service is already active
      if ! systemctl is-active dev-mapper-swap.swap &>/dev/null; then
        # Try to start the swap service
        systemctl start dev-mapper-swap.swap || true
      fi
    '';
  };
}

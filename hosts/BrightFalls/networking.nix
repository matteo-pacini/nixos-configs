_: {
  networking.hostName = "BrightFalls";

  networking.firewall = {
    enable = true;
    trustedInterfaces = [ "tailscale0" ];
  };

  networking.networkmanager.enable = true;

  # Wi-Fi starts every boot with the radio off. NetworkManager keeps the last
  # radio state in its state file, defaults to on when the key is missing, and
  # pushes that state to the kernel rfkill switch when it starts; no
  # NetworkManager.conf key sets a default. So this sets WirelessEnabled=false
  # before NetworkManager first reads the file, keeping the file's other keys.
  # Once per boot, because NetworkManager reads the file again whenever it
  # restarts: a second run mid-session would turn off a radio the user turned
  # on. RemainAfterExit keeps the unit active, so a NetworkManager restart does
  # not start it again; restartIfChanged = false keeps a switch from re-running
  # it when this unit changes.
  systemd.services.wifi-radio-off-at-boot = {
    description = "Start NetworkManager with the Wi-Fi radio off";
    wantedBy = [ "NetworkManager.service" ];
    before = [ "NetworkManager.service" ];
    restartIfChanged = false;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # NetworkManager.service declares the same directory, but only for itself.
      StateDirectory = "NetworkManager";
    };
    # The state file as an optional argument only so the script can be run
    # against a copy; the unit passes none.
    script = ''
      state=''${1:-/var/lib/NetworkManager/NetworkManager.state}
      key='^WirelessEnabled[[:space:]]*='
      if [ ! -e "$state" ]; then
        printf '[main]\nWirelessEnabled=false\n' > "$state"
      elif grep -q "$key" "$state"; then
        sed -i "s/$key.*/WirelessEnabled=false/" "$state"
      elif grep -q '^\[main\]' "$state"; then
        sed -i '/^\[main\]/a WirelessEnabled=false' "$state"
      else
        printf '\n[main]\nWirelessEnabled=false\n' >> "$state"
      fi
    '';
  };

  # Enable Wake-on-LAN for the Ethernet interface
  networking.interfaces.enp2s0.wakeOnLan.enable = true;

  # IPv6 disabled

  networking.enableIPv6 = false;

  services.tailscale.enable = true;
}

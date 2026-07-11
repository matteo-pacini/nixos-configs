{ ... }:
{
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
    ports = [ 1788 ];
    # Password login for matteo from the HOME VLAN only (installer ISO
    # restore path). Tailnet (100.64.0.0/10) and WAN sources never match
    # this block, so they stay key-only. Requires matteo to have a
    # password on Nexus (mutableUsers: set once with `passwd`).
    extraConfig = ''
      Match User matteo Address 192.168.10.0/24
        PasswordAuthentication yes
    '';
  };
}

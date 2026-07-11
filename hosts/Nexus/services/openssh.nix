{ lib, ... }:
{
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      # Keyboard-interactive defaults to on and is offered to every source,
      # routing to the same PAM auth stack. With unixAuth forced on below it
      # would become password login from WAN/tailnet/any VLAN. Off globally;
      # the Match block re-enables only the `password` method for the LAN.
      KbdInteractiveAuthentication = false;
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

  # NixOS ties security.pam.services.sshd.unixAuth to the *global*
  # PasswordAuthentication (false here), which strips pam_unix from the sshd
  # PAM auth stack — leaving only pam_deny. That makes the Match-block
  # password path above impossible: PAM denies before the password is ever
  # checked. Force pam_unix back into the auth stack; the SSH-layer Match
  # block is the gate for who may actually use password auth.
  security.pam.services.sshd.unixAuth = lib.mkForce true;
}

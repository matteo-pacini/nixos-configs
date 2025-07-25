{
  isVM,
  pkgs,
  lib,
  ...
}:
{
  programs.zsh.enable = true;

  programs.command-not-found.enable = true;

  users.users."matteo" = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "audio"
      "video"
      "input"
      "corectrl"
      "docker"
      "kvm"
    ];
    shell = pkgs.zsh;
    initialPassword = lib.optionalString (isVM) "ziosasso";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMnZQbZ02mIPzak2QNgH6CWZScxC4rdQVACEBmC0mNAf matteo@Nexus"
    ];
  };

  security.sudo.extraRules = [
    {
      users = [ "matteo" ];
      commands = [
        {
          command = "${pkgs.systemd}/bin/shutdown";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

}

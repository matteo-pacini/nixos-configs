{
  pkgs,
  ...
}:
{
  programs.zsh.enable = true;

  programs.command-not-found.enable = true;

  users.users."antonella" = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "audio"
      "video"
      "input"
    ];
    shell = pkgs.zsh;
  };

}

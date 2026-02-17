{ ... }:
{
  custom.zsh = {
    enable = true;
    powerlevel10k = {
      enable = true;
      configSource = ./dot_p10k.zsh;
    };
  };

  custom.shell-tools.enable = true;

  custom.atuin = {
    enable = true;
    syncAddress = "http://localhost:8888";
  };
}

{ ... }:
{
  custom.zsh = {
    enable = true;
    suggestionAliases = true;
    powerlevel10k = {
      enable = true;
      configSource = ./dot_p10k.zsh;
    };
  };

  custom.shell-tools.enable = true;

  custom.atuin = {
    enable = true;
    syncAddress = "http://nexus-ts.walrus-draconis.ts.net:8888";
  };
}

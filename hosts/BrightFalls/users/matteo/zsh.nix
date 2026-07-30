{ ... }:
{
  custom.zsh = {
    enable = true;
    suggestionAliases = true;
  };

  custom.shell-tools.enable = true;

  custom.atuin = {
    enable = true;
    syncAddress = "http://nexus-ts.walrus-draconis.ts.net:8888";
  };
}

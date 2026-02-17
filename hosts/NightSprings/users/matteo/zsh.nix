{ ... }:
{
  custom.zsh = {
    enable = true;
    suggestionAliases = true;
    darwinAliases = true;
  };

  custom.shell-tools = {
    enable = true;
    fzf.batPreview = true;
  };

  custom.atuin = {
    enable = true;
    syncAddress = "http://nexus-ts.walrus-draconis.ts.net:8888";
  };
}

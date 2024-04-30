{
  config,
  pkgs,
  inputs,
  ...
}: {
  programs.vscode = {
    enable = true;
    extensions = let
      vscext = pkgs.vscode-extensions;
    in [
      vscext.jnoortheen.nix-ide
      vscext.kamadorueda.alejandra
      vscext.github.copilot
      vscext.usernamehw.errorlens
      vscext.timonwong.shellcheck
    ];
    mutableExtensionsDir = false;
    userSettings = {
      "nix.formatterPath" = "alejandra";
      "editor.fontSize" = 16;
    };
  };
}

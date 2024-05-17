{
  config,
  pkgs,
  inputs,
  ...
}: {
  programs.vscode = {
    enable = true;
    package = pkgs.unstable.vscode;
    enableUpdateCheck = false;
    enableExtensionUpdateCheck = false;
    extensions = let
      vscext = pkgs.unstable.vscode-extensions;
    in [
      vscext.jnoortheen.nix-ide
      vscext.kamadorueda.alejandra
      vscext.github.copilot
      vscext.usernamehw.errorlens
      vscext.timonwong.shellcheck
      vscext.dracula-theme.theme-dracula
    ];
    mutableExtensionsDir = false;
    userSettings = {
      "nix.formatterPath" = "alejandra";
      "editor.fontSize" = 16;
      "editor.fontFamily" = "FiraCode Nerd Font";
      "workbench.colorTheme" = "Dracula";
    };
  };
}
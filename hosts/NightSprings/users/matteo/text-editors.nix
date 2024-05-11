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
      vscext.catppuccin.catppuccin-vsc
      vscext.golang.go
    ];
    mutableExtensionsDir = false;
    userSettings = {
      "nix.formatterPath" = "alejandra";
      "editor.fontSize" = 16;
      "workbench.colorTheme" = "Catppuccin Mocha";
      # Catppuccin recommended settings
      "editor.semanticHighlighting.enabled" = true;
      "terminal.integrated.minimumContrastRatio" = 1;
      "window.titleBarStyle" = "custom";
      "gopls.ui.semanticTokens" = true;
    };
  };
}

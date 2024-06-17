{ pkgs, ... }:
{
  programs.vscode = {
    enable = true;
    package = pkgs.unstable.vscode;
    enableUpdateCheck = false;
    enableExtensionUpdateCheck = false;
    extensions =
      let
        vscext = pkgs.unstable.vscode-extensions;
      in
      [
        vscext.jnoortheen.nix-ide
        vscext.github.copilot
        vscext.usernamehw.errorlens
        vscext.timonwong.shellcheck
        vscext.golang.go
        vscext.eamodio.gitlens
      ];
    mutableExtensionsDir = false;
    userSettings = {
      "nix.enableLanguageServer" = true;
      "nix.formatterPath" = "${pkgs.nixfmt-rfc-style}/bin/nixfmt";
      "nix.serverPath" = "${pkgs.nil}/bin/nil";
      "nix.serverSettings" = {
        "nil" = {
          "formatting" = {
            "command" = [ "${pkgs.nixfmt-rfc-style}/bin/nixfmt" ];
          };
        };
      };
      "[nix]" = {
        "editor.tabSize" = 2;
        "editor.detectIndentation" = true;
        "editor.formatOnSave" = true;
      };
      "editor.fontSize" = 16;
      "editor.fontFamily" = "FiraCode Nerd Font";
      "telemetry.telemetryLevel" = "off";
      "redhat.telemetry.enabled" = false;
    };
  };
}

{ pkgs, lib, ... }:
let
  vscode-utils = pkgs.vscode-utils;
  perlnavigator = vscode-utils.extensionFromVscodeMarketplace {
    name = "perlnavigator";
    publisher = "bscan";
    version = "0.8.12";
    hash = "sha256-LozWG8ZfAkYr55aIzYldQDDe2rUM95l76EeJPCaGOCM=";
  };
in
{
  programs.vscode = {
    enable = true;
    package = pkgs.unstable.vscodium;
    enableUpdateCheck = false;
    enableExtensionUpdateCheck = false;
    extensions =
      let
        vscext = pkgs.unstable.vscode-extensions;
      in
      with vscext;
      [
        # Editor
        editorconfig.editorconfig
        mhutchie.git-graph
        usernamehw.errorlens
        vscext.eamodio.gitlens
        # Copilot
        github.copilot
        # Nix
        jnoortheen.nix-ide
        # Go
        golang.go
        # Shell
        vscext.timonwong.shellcheck
        # Rust
        vscext.rust-lang.rust-analyzer
        vscext.tamasfe.even-better-toml
        vscext.serayuzgur.crates
        # Perl
        perlnavigator
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
    };
  };
}

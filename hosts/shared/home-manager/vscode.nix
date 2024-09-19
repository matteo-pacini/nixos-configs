{ pkgs, ... }:

{
  programs.vscode = {
    enable = true;
    package = pkgs.vscodium;
    enableUpdateCheck = false;
    enableExtensionUpdateCheck = false;
    extensions =
      let
        vscext = pkgs.vscode-extensions;
      in
      (
        with vscext;
        [
          # Editor
          editorconfig.editorconfig
          mhutchie.git-graph
          usernamehw.errorlens
          vscext.eamodio.gitlens
          # Live share
          ms-vsliveshare.vsliveshare
          # Nix
          jnoortheen.nix-ide
          # Go
          golang.go
          # Shell
          timonwong.shellcheck
          # Rust
          rust-lang.rust-analyzer
          tamasfe.even-better-toml
          # Yaml
          redhat.vscode-yaml
        ]
        ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
          {
            name = "copilot";
            publisher = "GitHub";
            version = "1.231.1112";
            sha256 = "sha256-7Xqd7YeiDlR1ygc8vhPXqYQy7agHqypFIDbESr0htKk=";
          }
          {
            name = "perlnavigator";
            publisher = "bscan";
            version = "0.8.15";
            hash = "sha256-IClcFvP86NdCtAhwkPgwG4pbGGEou4h2YVul+AAuZow=";
          }
          {
            name = "dependi";
            publisher = "fill-labs";
            version = "0.7.9";
            hash = "sha256-VsjISVDZGGh6/pf3Fd5g8pYDvWXA1+0oZKlQEGLBp4M=";
          }
        ]
      );
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
      "[yaml]" = {
        "editor.defaultFormatter" = "redhat.vscode-yaml";
        "editor.tabSize" = 2;
        "editor.detectIndentation" = true;
        "editor.formatOnSave" = true;
      };
      # Telemetry
      "telemetry.telemetryLevel" = "off";
      "redhat.telemetry.enabled" = false;
    };
  };
}

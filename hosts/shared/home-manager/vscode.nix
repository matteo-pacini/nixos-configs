{ pkgs, ... }:

{
  programs.vscode = {
    enable = true;
    package = pkgs.vscodium;
    mutableExtensionsDir = false;
    profiles = {
      default = {
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
              eamodio.gitlens
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
              # rust-lang.rust-analyzer
              tamasfe.even-better-toml
              # Yaml
              redhat.vscode-yaml
              # Copilot
              github.copilot
              # JS/TS
              esbenp.prettier-vscode
              dbaeumer.vscode-eslint
            ]
            ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
              {
                name = "perlnavigator";
                publisher = "bscan";
                version = "0.8.15";
                hash = "sha256-IClcFvP86NdCtAhwkPgwG4pbGGEou4h2YVul+AAuZow=";
              }
              {
                name = "dependi";
                publisher = "fill-labs";
                version = "0.7.13";
                hash = "sha256-Xn2KEZDQ11LDfUKbIrJtQNQXkcusyrL/grDyQxUmTbc=";
              }
              {
                name = "claude-dev";
                publisher = "saoudrizwan";
                version = "3.11.0";
                hash = "sha256-JWTcr1M1GUeO9ved382xTra4vlcAtKdcSc6kouWerB8=";
              }
            ]
          );
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
    };
  };
}

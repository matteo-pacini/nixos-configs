{
  pkgs,

  ...
}:
let
  clineSettings =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "Library/Application Support/VSCodium/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json"
    else
      ".config/VSCodium/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json";
in
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
                version = "0.7.14";
                hash = "sha256-iLF2kxhSw39JBIs5K6hVmrEKueS8C22rnKCs+CiphwY=";
              }
              {
                name = "claude-dev";
                publisher = "saoudrizwan";
                version = "3.15.5";
                hash = "sha256-J6TQnAfgjsg5bWKchsbBRfIK+2XCrYaVsOgYZFiLASA=";
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

  home.file."${clineSettings}".text = ''
    {
      "mcpServers": {
        "github.com/upstash/context7-mcp": {
          "command": "${pkgs.nodejs}/bin/npx",
          "args": ["-y", "@upstash/context7-mcp@latest"],
          "disabled": false,
          "autoApprove": []
        }
      }
    }
  '';
}

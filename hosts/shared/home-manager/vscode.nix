{
  pkgs,
  config,
  ...
}:
let
  targetFolder = if config.programs.vscode.package == pkgs.vscode then "Code" else "VSCodium";
  clineSettings =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "Library/Application Support/${targetFolder}/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json"
    else
      ".config/${targetFolder}/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json";
in
{
  programs.vscode = {
    enable = true;
    package = pkgs.vscode;
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
              # Toml
              tamasfe.even-better-toml
              # Yaml
              redhat.vscode-yaml
              # Copilot
              github.copilot
              github.copilot-chat
              # JS/TS
              esbenp.prettier-vscode
              dbaeumer.vscode-eslint
              # LLMs
              saoudrizwan.claude-dev
              # GHA
              github.vscode-github-actions
            ]
            ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
              {
                name = "perlnavigator";
                publisher = "bscan";
                version = "0.8.19";
                hash = "sha256-ID77fDLSnyRY1sYCiM9eqDDiy+Ml04lBKaPoRtujMoo=";
              }
              {
                name = "dependi";
                publisher = "fill-labs";
                version = "0.7.15";
                hash = "sha256-BXilurHO9WATC0PhT/scpZWEiRhJ9cSlq59opEM6wlE=";
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

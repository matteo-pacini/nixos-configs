{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.vscode;
  targetFolder = if config.programs.vscode.package == pkgs.vscode then "Code" else "VSCodium";
in
{
  options.custom.vscode = {
    enable = lib.mkEnableOption "VS Code configuration with extensions and settings";
  };

  config = lib.mkIf cfg.enable {
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
                editorconfig.editorconfig
                mhutchie.git-graph
                usernamehw.errorlens
                (pkgs.vscode-utils.buildVscodeMarketplaceExtension {
                  mktplcRef = {
                    name = "gitlens";
                    publisher = "eamodio";
                    version = "17.7.1";
                    hash = "sha256-8RFsgmGIOtydML/1AEeOEbs1r1vH5tmKJZpX9lC+i/g=";
                  };

                  meta = {
                    changelog = "https://marketplace.visualstudio.com/items/eamodio.gitlens/changelog";
                    description = "Visual Studio Code extension that improves its built-in Git capabilities";
                    longDescription = ''
                      Supercharge the Git capabilities built into Visual Studio Code — Visualize code authorship at a glance via Git
                      blame annotations and code lens, seamlessly navigate and explore Git repositories, gain valuable insights via
                      powerful comparison commands, and so much more
                    '';
                    downloadPage = "https://marketplace.visualstudio.com/items?itemName=eamodio.gitlens";
                    homepage = "https://gitlens.amod.io/";
                    license = lib.licenses.mit;
                  };
                })
                ms-vsliveshare.vsliveshare
                jnoortheen.nix-ide
                golang.go
                timonwong.shellcheck
                tamasfe.even-better-toml
                redhat.vscode-yaml
                github.copilot
                github.copilot-chat
                esbenp.prettier-vscode
                dbaeumer.vscode-eslint
                github.vscode-github-actions
                charliermarsh.ruff
                ms-python.python
                ms-python.vscode-pylance
                ms-python.mypy-type-checker
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
            "nix.formatterPath" = "${pkgs.nixfmt}/bin/nixfmt";
            "nix.serverPath" = "${pkgs.nil}/bin/nil";
            "nix.serverSettings" = {
              "nil" = {
                "formatting" = {
                  "command" = [ "${pkgs.nixfmt}/bin/nixfmt" ];
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
            "telemetry.telemetryLevel" = "off";
            "redhat.telemetry.enabled" = false;
          };
        };
      };
    };
  };
}

{
  pkgs,
  ...
}:
{
  programs.vscode = {
    profiles = {
      default = {
        extensions = pkgs.vscode-utils.extensionsFromVscodeMarketplace [
          {
            name = "vscode-augment";
            publisher = "augment";
            version = "0.561.0";
            hash = "sha256-9vkJwZmBVLRsmnRtzLEV2hOz561y5xuibbAiQbxKYtY=";
          }
        ];
      };
    };
  };

}

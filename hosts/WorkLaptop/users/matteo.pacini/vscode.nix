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
            version = "0.545.0";
            hash = "sha256-SnSkX6Y/qLKh5w0YMgf01M7esD2BcJzeOGC2zcGnFsI=";
          }
        ];
      };
    };
  };

}

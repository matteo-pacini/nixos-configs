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
            version = "0.541.0";
            hash = "sha256-ClwHDwTO5TntIK4YNQm03Zr1RX0SSa1f5rrWK6rJ4tE=";
          }
        ];
      };
    };
  };

}

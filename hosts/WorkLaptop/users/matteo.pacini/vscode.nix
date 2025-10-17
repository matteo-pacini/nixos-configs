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
            version = "0.596.2";
            hash = "sha256-T75GltdyN5/HSu/N5SvcrBypT0PV5bl4rfgYyOx388Q=";
          }
        ];
      };
    };
  };

}

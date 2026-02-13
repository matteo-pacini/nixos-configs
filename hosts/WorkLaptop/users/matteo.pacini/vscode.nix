{
  pkgs,
  ...
}:
{
  programs.vscode = {
    profiles = {
      default = {
        extensions = with pkgs.vscode-extensions; [
          augment.vscode-augment
        ];
      };
    };
  };

}

{
  config,
  pkgs,
  inputs,
  ...
}: {
  programs.xcodes = {
    enable = true;
    enableAria = true;
    versions = [
      "15.4"
    ];
    active = "15.4";
  };
}

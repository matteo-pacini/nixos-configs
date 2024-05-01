{
  config,
  pkgs,
  inputs,
  ...
}: {
  programs.xcodes = {
    enable = true;
    useAria = true;
    versions = ["15.3"];
    active = "15.3";
  };
}

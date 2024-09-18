{ ... }:
{
  programs.xcodes = {
    enable = true;
    enableAria = true;
    versions = [
      "15.4"
      "16.0"
    ];
    active = "15.4";
  };
}

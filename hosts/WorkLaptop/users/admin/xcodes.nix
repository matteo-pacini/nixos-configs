{ ... }:
{
  programs.xcodes = {
    enable = true;
    enableAria = true;
    versions = [
      "15.4"
      "16.0"
      "16.1 Beta 2"
    ];
    active = "15.4";
  };
}

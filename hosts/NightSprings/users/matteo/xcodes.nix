{ ... }:
{
  programs.xcodes = {
    enable = true;
    enableAria = true;
    versions = [
      "16.0"
      "16.1 Beta 2"
    ];
    active = "16.0";
  };
}

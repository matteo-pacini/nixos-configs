{ ... }:
{
  programs.xcodes = {
    enable = true;
    enableAria = true;
    versions = [
      "15.4"
      "16.0 Beta 4"
    ];
    active = "15.4";
  };
}

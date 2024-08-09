{ ... }:
{
  programs.xcodes = {
    enable = true;
    enableAria = true;
    versions = [
      "15.4"
      "16.0 Beta 5"
    ];
    active = "15.4";
  };
}

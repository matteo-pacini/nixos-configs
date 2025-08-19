{ ... }:
{
  programs.xcodes = {
    enable = true;
    versions = [
      "16.4"
      "26.0 Beta 6"
    ];
    active = "16.4";
  };
}

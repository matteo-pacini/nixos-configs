{ ... }:
{
  programs.xcodes = {
    enable = true;
    versions = [
      "16.4"
      "26.0 Beta"
    ];
    active = "16.4";
  };
}

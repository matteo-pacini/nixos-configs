{ ... }:
{
  programs.xcodes = {
    enable = true;
    versions = [
      "16.2"
      "16.3"
    ];
    active = "16.2";
  };
}
